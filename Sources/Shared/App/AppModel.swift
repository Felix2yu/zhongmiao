import Foundation
import Observation
import UserNotifications
import WebKit
import ZhongmiaoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// `loadServerNtfyTopics()` 的失败原因（`Result` 的 Failure 需要符合 `Error`）。
struct NtfyTopicsError: Error, Sendable {
    var message: String
}

/// 应用状态中枢。
///
/// 约定：
/// - 所有 UI 可写状态都在主线程；
/// - 网络与磁盘在 actor / URLSession 里完成，结果回主线程合并；
/// - 设置变更即落盘（UserDefaults），崩溃也不会丢配置。
@MainActor
@Observable
final class AppModel {

    static let shared = AppModel()

    // MARK: - 可观察状态

    var settings: AppSettings
    private(set) var snapshot: NotificationSnapshot = .empty
    private(set) var health: [String: ServiceHealth] = [:]
    private(set) var isSyncing = false
    private(set) var isProbing = false
    private(set) var lastReport: SyncReport?
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var pushToken: String?
    private(set) var pushError: String?
    private(set) var log: [String] = []
    /// 独立订阅的 ntfy 主题（不属于任何应用），按需轮询进收件箱。
    private(set) var ntfyTopics: [String]
    /// 缓存中尚未散场的演出，供设置页展示与提醒排程使用。
    private(set) var shows: [Show] = []
    var toast: String?
    /// 通知点击 / 系统深链请求打开的服务页。
    var pendingRoute: Route?

    let network = NetworkMonitor()
    let integrations: IntegrationCenter

    private let scheduler: NotificationScheduler
    private let engine: NotificationEngine
    private let feeds = FeedClients()
    private let showStore = ShowStore.standard()
    private let showScheduler = ShowScheduler()
    private var notificationDelegate: NotificationDelegate?
    private var observers: [NSObjectProtocol] = []
    private var hasActivated = false
    /// 服务端上次拒绝「标记已读」时用的令牌。换了令牌才值得再试。
    private var ntfyRejectedToken: String?

    // MARK: - 页面路由

    struct Route: Hashable, Identifiable {
        var serviceID: String
        var url: URL?
        /// 原生页内的具体条目（某场演出、某天日记…）。点通知直达这一条。
        var target: NativeTarget?
        /// 用户在原生页里主动切到网页版，或设置里勾了“优先网页版”。
        var preferWeb: Bool

        var id: String {
            let targetPart = target.map { "\($0.kind)=\($0.identifier)" } ?? "root"
            return "\(serviceID)#\(url?.absoluteString ?? "root")#\(targetPart)#\(preferWeb)"
        }

        init(serviceID: String, url: URL? = nil, target: NativeTarget? = nil, preferWeb: Bool = false) {
            self.serviceID = serviceID
            self.url = url
            self.target = target
            self.preferWeb = preferWeb
        }
    }

    // MARK: - 初始化

    private init() {
        #if DEBUG
        IntegrationDebugSeed.applyIfNeeded()
        #endif
        // 先迁移明文密钥，再读设置；迁移成功后原始 JSON 里的键会被删除。
        let migration = LegacySecretMigration.run()
        let secrets = SecretStore()
        self.integrations = IntegrationCenter(secrets: secrets)

        let settings = SettingsStorage.load()
        self.settings = settings
        self.ntfyTopics = NtfySubscriptionStore.load()
        let scheduler = NotificationScheduler()
        self.scheduler = scheduler
        self.engine = NotificationEngine(scheduler: scheduler, capacity: settings.inboxCapacity)

        if !migration.isEmpty {
            appendLog("密钥迁移：\(migration.logText)")
        }
        #if DEBUG
        if let preview = IntegrationDebugSeed.previewServiceID {
            pendingRoute = Route(serviceID: preview)
        }
        // 调试用：直接注入一个原生条目目标，验证「点通知直达某一条」。
        if let target = IntegrationDebugSeed.nativeTarget,
           let serviceID = IntegrationDebugSeed.nativeTargetServiceID,
           ServiceCatalog.service(id: serviceID) != nil {
            pendingRoute = Route(serviceID: serviceID, target: target)
        }
        #endif
    }

    // 旧调用点仍按属性读取；实际值来自 Keychain。
    var mujianToken: String { integrations.secrets.value(for: .mujian) }
    var ntfyToken: String { integrations.secrets.value(for: .ntfy) }
    var relaySecret: String { integrations.secrets.value(for: .relay) }

    /// 由 AppDelegate 调用：注册通知代理、启动网络监听。必须早于页面加载。
    func activate() {
        guard !hasActivated else { return }
        hasActivated = true

        scheduler.registerCategories()
        showScheduler.registerCategories()
        integrations.registerReminderCategory()

        let delegate = NotificationDelegate(
            onOpen: { serviceID, urlString, target in
                Task { @MainActor in
                    AppModel.shared.handleNotificationOpen(serviceID: serviceID, urlString: urlString, target: target)
                }
            },
            onShowAction: { action, showID in
                Task { @MainActor in
                    AppModel.shared.handleShowAction(action, showID: showID)
                }
            },
            onIntegrationOpen: { serviceID, target in
                Task { @MainActor in
                    AppModel.shared.handleIntegrationNotification(serviceID: serviceID, target: target)
                }
            }
        )
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        network.onReconnect = { [weak self] in
            self?.handleReconnect()
        }
        network.start()

        NotificationCenter.default.addObserver(
            forName: .zhongmiaoPushToken,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let token = note.object as? String
            Task { @MainActor in self?.handlePushToken(token) }
        }

        appendLog("启动完成 · \(Platform.platformName)")
    }

    /// 首帧后执行：刷新快照、申请状态、触发一次同步。
    func bootstrap() async {
        refreshSnapshot()
        authorization = await scheduler.authorizationStatus()
        if await scheduler.isDeliveryAllowed() {
            registerForRemoteNotifications()
        }
        scheduleBackgroundRefresh()
        syncNow(reason: "启动")
        #if DEBUG
        if IntegrationDebugSeed.previewServiceID == nil {
            await refreshShows()
        }
        #else
        await refreshShows()
        #endif
        Task { await validateIntegrationsOnLaunch() }
    }

    /// 冷启动静默验证已配置的原生接入；未配置的应用不发起请求。
    func validateIntegrationsOnLaunch() async {
        // 逐个校验。并发跑会把主线程压满（每个不可达的服务要等满 15s 超时），
        // 连带 UI 自动化都插不进事件，所以这里坚持串行。
        // 但要把「用户正要打开的那个应用」排到最前，否则点进去先看到一堆加载中。
        var ordered = IntegrationCatalog.integrated
        if let pending = pendingRoute?.serviceID,
           let index = ordered.firstIndex(where: { $0.serviceID == pending }),
           index > 0 {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        for definition in ordered {
            guard let service = ServiceCatalog.service(id: definition.serviceID),
                  let baseURL = url(for: service) else { continue }
            await integrations.validateIfConfigured(serviceID: definition.serviceID, baseURL: baseURL)
        }
    }

    // MARK: - 演出

    /// 刷新演出缓存并重排提醒。
    ///
    /// 两个数据源各自失败都只记日志、不清缓存：一次网络抖动不该让已经排好的提醒消失。
    func refreshShows() async {
        guard settings.showsEnabled else {
            await showScheduler.cancelAll()
            shows = []
            return
        }

        let outcome = await showStore.refresh(settings: settings, token: mujianToken)
        shows = outcome.library.upcoming()

        if let error = outcome.apiError { appendLog("幕间演出拉取失败：\(error)") }
        if let error = outcome.calendarError { appendLog("日历读取失败：\(error)") }

        await syncShowReminders()
        await alignShowIsland()
    }

    /// 打开 App 也是开岛触发点之一：命中窗口就直接亮起来，不必等自动化。
    ///
    /// 硬约束：`Activity.request` 要求 App 处于 **active**，否则直接抛
    /// `Target is not foreground`。冷启动时刷新演出是在 `didFinishLaunching` 阶段发起的，
    /// 那一刻还没 active，这一下必然失败。
    ///
    /// 处理方式：**不拦截**，照样发请求，失败也不打扰用户——`scenePhase` 变为 active 时
    /// 会自动重试一次。之所以不能用「前台才发」来挡，是因为快捷指令跑 `LiveActivityIntent`
    /// 时 App 同样不在前台，挡掉就把主力触发路径一起废了。
    func alignShowIsland() async {
        #if os(iOS)
        guard settings.showsEnabled else {
            await ShowIslandController.shared.endAll()
            return
        }
        let outcome = await ShowIslandController.shared.align(
            shows: shows,
            lead: settings.showsIslandLead
        )
        if !outcome.isSuccess, UIApplication.shared.applicationState == .active {
            appendLog("灵动岛：\(outcome.logText)")
        }
        #endif
    }

    /// 把当前缓存重排成系统通知。提前量或开关变动后单独调用即可，无需重新联网。
    func syncShowReminders() async {
        guard settings.showsEnabled else { return }
        await showScheduler.sync(shows, lead: settings.showsReminderLead)
    }

    /// 演出通知上的按钮。
    func handleShowAction(_ action: String, showID: String) {
        guard let show = shows.first(where: { $0.id == showID }) else { return }
        switch action {
        case ShowScheduler.watchActionIdentifier:
            // 通知把 App 拉到前台，此刻开岛必成——这是唯一 100% 可靠的开岛路径。
            #if os(iOS)
            Task { @MainActor in
                let outcome = await ShowIslandController.shared.align(
                    shows: AppModel.shared.shows,
                    lead: AppModel.shared.settings.showsIslandLead
                )
                AppModel.shared.appendLog("盯场：\(outcome.logText)")
            }
            #endif
            openShow(show)
        default:
            openShow(show)
        }
    }

    private func openShow(_ show: Show) {
        guard let service = ServiceCatalog.service(id: "mujian") else { return }
        pendingRoute = Route(serviceID: service.id, url: show.url ?? url(for: service))
    }

    // MARK: - 地址解析

    func url(for service: ServiceDefinition) -> URL? {
        #if DEBUG
        if let previewURL = IntegrationDebugSeed.baseURL(for: service.id) {
            return previewURL
        }
        #endif
        return ServiceURLResolver.url(
            for: service,
            settings: settings.addressing,
            override: settings.preference(for: service).urlOverride
        )
    }

    func url(for route: Route) -> URL? {
        guard let service = ServiceCatalog.service(id: route.serviceID) else { return nil }
        if let exact = route.url { return exact }
        return url(for: service)
    }

    /// ntfy 的服务器地址。
    ///
    /// ntfy 本身也是一个服务，地址覆盖统一写在「服务与接入 → ntfy」里，
    /// 与主题浏览、通知同步共用同一份配置。旧版本把这一项单独存在
    /// `ntfyBaseURLOverride`（「ntfy 主题」页里那个输入框），仍作为回落读取一次，
    /// 避免升级后已填的地址失效。
    func resolvedNtfyBase() -> URL? {
        guard let service = ServiceCatalog.service(id: "ntfy") else { return nil }
        let serviceOverride = settings.preference(for: service).urlOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !serviceOverride.isEmpty {
            return url(for: service)
        }
        let legacy = settings.ntfyBaseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            let normalized = legacy.contains("://") ? legacy : "https://" + legacy
            return URL(string: normalized)
        }
        return url(for: service)
    }

    func relayURL() -> URL? {
        let raw = settings.relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw.contains("://") ? raw : "https://" + raw)
    }

    // MARK: - ntfy 主题订阅

    /// 订阅一个 ntfy 主题。返回错误文案；成功后立即同步一次。
    @discardableResult
    func subscribeNtfyTopic(_ raw: String) -> String? {
        guard let topic = NtfyTopic.normalized(raw) else {
            return NtfyTopic.validationMessage(for: raw) ?? "主题名不合法"
        }
        guard !ntfyTopics.contains(topic) else { return nil }
        ntfyTopics.append(topic)
        NtfySubscriptionStore.save(ntfyTopics)
        appendLog("订阅 ntfy 主题：\(topic)")
        syncNow(reason: "订阅 ntfy 主题")
        return nil
    }

    func unsubscribeNtfyTopic(_ topic: String) {
        guard ntfyTopics.contains(topic) else { return }
        ntfyTopics.removeAll { $0 == topic }
        NtfySubscriptionStore.save(ntfyTopics)
        appendLog("取消订阅 ntfy 主题：\(topic)")
    }

    func isNtfyTopicSubscribed(_ topic: String) -> Bool {
        ntfyTopics.contains(topic)
    }

    /// 拉取服务器上已有缓存消息的主题（`GET /v1/topics`，不要求鉴权）。
    func loadServerNtfyTopics() async -> Result<[String], NtfyTopicsError> {
        guard let base = resolvedNtfyBase() else {
            return .failure(NtfyTopicsError(
                message: "还没有可用的 ntfy 地址。先到「接入方式」配置基础域名，或在本页填写 ntfy 地址。"
            ))
        }
        do {
            return .success(try await feeds.fetchNtfyTopics(base: base, token: ntfyToken))
        } catch {
            return .failure(NtfyTopicsError(message: Self.describe(error)))
        }
    }

    // MARK: - 同步

    func buildTargets() -> [SyncTarget] {
        let ntfyBase = resolvedNtfyBase()
        let relay = relayURL()
        var targets: [SyncTarget] = []

        for service in ServiceCatalog.all {
            let pref = settings.preference(for: service)
            guard pref.notificationsEnabled else { continue }
            guard let base = url(for: service) else { continue }

            let feedPath = pref.feedPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            let topic = pref.ntfyTopic?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasFeed = !(feedPath ?? "").isEmpty
            let hasTopic = !(topic ?? "").isEmpty

            // 有专属通道就不再走中继，避免同一条事件被拉两次（虽然去重能兜住）。
            let useRelay = relay != nil && !hasFeed && !hasTopic
            guard hasFeed || hasTopic || useRelay else { continue }

            targets.append(
                SyncTarget(
                    serviceID: service.id,
                    serviceName: service.name,
                    baseURL: base,
                    feedPath: hasFeed ? feedPath : nil,
                    ntfyTopic: hasTopic ? topic : nil,
                    ntfyBaseURL: hasTopic ? ntfyBase : nil,
                    ntfyToken: ntfyToken,
                    relayURL: useRelay ? relay : nil,
                    relaySecret: relaySecret
                )
            )
        }

        // 独立订阅的主题：不属于任何应用，用 `ntfy:<topic>` 当伪服务 id，
        // 让游标、去重键与展示都按主题分开（详见 NtfyTopic）。
        if let ntfyBase {
            for topic in ntfyTopics {
                targets.append(
                    SyncTarget(
                        serviceID: NtfyTopic.serviceID(for: topic),
                        serviceName: topic,
                        baseURL: ntfyBase,
                        feedPath: nil,
                        ntfyTopic: topic,
                        ntfyBaseURL: ntfyBase,
                        ntfyToken: ntfyToken,
                        relayURL: nil,
                        relaySecret: ""
                    )
                )
            }
        }
        return targets
    }

    func syncNow(reason: String = "手动") {
        guard !isSyncing else { return }
        isSyncing = true
        let targets = buildTargets()
        let online = network.isOnline
        let lookback = settings.lookbackHours

        Task {
            let result = await engine.sync(targets: targets, isOnline: online, lookbackHours: lookback)
            snapshot = result.snapshot
            lastReport = result.report
            isSyncing = false
            appendLog("同步（\(reason)）：\(result.report.summaryText)")
            if reason == "手动" || result.report.inserted > 0 {
                toast = result.report.summaryText
            }
        }
    }

    /// 重连：先把积压投递掉，再全量补拉一次。
    func handleReconnect() {
        appendLog("网络已恢复，开始补发")
        syncNow(reason: "重连")
    }

    func refreshSnapshot() {
        Task {
            snapshot = await engine.snapshot(isSyncing: isSyncing)
        }
    }

    // MARK: - 通知权限与推送

    func requestNotificationPermission() async {
        let granted = await scheduler.requestAuthorization()
        authorization = await scheduler.authorizationStatus()
        appendLog(granted ? "已获通知授权" : "通知授权被拒绝")
        if granted {
            registerForRemoteNotifications()
            // 授权后立刻把此前积压的通知补发出去（这是"不丢通知"的关键一步）。
            let names = Dictionary(uniqueKeysWithValues: ServiceCatalog.all.map { ($0.id, $0.name) })
            let delivered = await engine.flushPending(serviceNames: names)
            snapshot = await engine.snapshot()
            if delivered > 0 {
                toast = "补发 \(delivered) 条历史通知"
            }
            syncNow(reason: "授权")
        }
    }

    func refreshAuthorization() {
        Task { authorization = await scheduler.authorizationStatus() }
    }

    func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func handlePushToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        pushToken = token
        uploadPushToken()
    }

    func uploadPushToken() {
        guard let token = pushToken, let relay = relayURL() else { return }
        let secret = relaySecret
        Task {
            do {
                try await feeds.registerDevice(
                    relay: relay,
                    secret: secret,
                    token: token,
                    platform: Platform.platformName,
                    deviceName: Platform.deviceName
                )
                appendLog("设备已注册到推送中继")
                pushError = nil
            } catch {
                pushError = error.localizedDescription
                appendLog("推送中继注册失败：\(error.localizedDescription)")
            }
        }
    }

    private func handleNotificationOpen(serviceID: String, urlString: String?, target: NativeTarget?) {
        // 独立订阅的主题没有应用页，统一落到 ntfy。
        let routeID = ServiceDisplay.routeServiceID(for: serviceID)
        guard ServiceCatalog.service(id: routeID) != nil else { return }
        let url = urlString.flatMap { raw -> URL? in
            guard !raw.isEmpty else { return nil }
            return URL(string: raw)
        }
        pendingRoute = Route(serviceID: routeID, url: url, target: target)
        appendLog("打开通知：\(routeID)")
    }

    private func handleIntegrationNotification(serviceID: String, target: NativeTarget?) {
        guard ServiceCatalog.service(id: serviceID) != nil else { return }
        pendingRoute = Route(serviceID: serviceID, target: target)
        appendLog(target.map { "打开原生提醒：\(serviceID) · \($0.kind)" } ?? "打开原生提醒：\(serviceID)")
    }

    // MARK: - 页面内通知

    func ingest(webNotification item: NotificationItem) {
        let name = ServiceCatalog.service(id: item.serviceID)?.name ?? item.serviceID
        Task {
            snapshot = await engine.ingest(item, serviceName: name)
        }
    }

    // MARK: - 收件箱操作

    func markRead(_ item: NotificationItem) {
        Task {
            snapshot = await engine.markRead(id: item.id)
            await pushReadStateToServer([item])
        }
    }

    func markAllRead(serviceID: String? = nil) {
        // 先记下要推送的条目：标记之后它们就都是已读状态了。
        let affected = snapshot.items.filter { item in
            (serviceID == nil || item.serviceID == serviceID) && !item.isRead
        }
        Task {
            snapshot = await engine.markAllRead(serviceID: serviceID)
            await pushReadStateToServer(affected)
        }
    }

    /// 把已读状态推回 ntfy 服务端，让网页版和其它设备也跟着变成已读。
    ///
    /// 服务端把它转成一条 `message_clear` 广播，订阅同一主题的人都会看到。
    /// 本地状态先落库，推送是尽力而为：推失败不影响本地，只是服务端暂时落后。
    private func pushReadStateToServer(_ items: [NotificationItem]) async {
        // 上次被服务端拒绝过就别再试了，除非令牌换了。
        guard ntfyRejectedToken != ntfyToken else { return }
        guard let base = resolvedNtfyBase() else { return }

        // 按主题分组：一个主题一次请求，服务端会按主题逐条广播。
        var byTopic: [String: [String]] = [:]
        for item in items {
            guard let topic = item.ntfyTopic, !topic.isEmpty else { continue }
            guard let target = item.ntfyTargetID else { continue }
            byTopic[topic, default: []].append(target)
        }
        guard !byTopic.isEmpty else { return }

        for (topic, ids) in byTopic {
            let outcome = await feeds.markNtfyRead(
                base: base,
                topic: topic,
                ids: ids,
                token: ntfyToken
            )
            switch outcome {
            case .accepted:
                appendLog("已读状态已同步到 ntfy：\(topic)（\(ids.count) 条）")
            case .notFound:
                appendLog("ntfy 上找不到 \(topic) 的这批消息，无需标记")
            case .rejected(let status):
                // 服务端拒绝写入：缺令牌或没有该主题的写权限，再试也没用。
                ntfyRejectedToken = ntfyToken
                appendLog("ntfy 拒绝标记已读（HTTP \(status)）：需要访问令牌或该主题的写权限")
            case .failed:
                appendLog("ntfy 标记已读失败：\(topic)")
            }
        }
    }

    func delete(_ item: NotificationItem) {
        Task { snapshot = await engine.remove(id: item.id) }
    }

    func clearInbox() {
        Task {
            snapshot = await engine.clearInbox()
            toast = "收件箱已清空"
        }
    }

    func openNotification(_ item: NotificationItem) {
        markRead(item)
        pendingRoute = Route(
            serviceID: ServiceDisplay.routeServiceID(for: item.serviceID),
            url: item.url
        )
    }

    // MARK: - 设置

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        settings = next
        SettingsStorage.save(next)
    }

    func persistSettings() {
        SettingsStorage.save(settings)
        Task { await engine.setCapacity(settings.inboxCapacity) }
    }

    func resetService(_ serviceID: String) {
        updateSettings { $0.servicePreferences[serviceID] = nil }
    }

    /// 置顶：只影响首页分组内的顺序，不动通知与地址。
    func setPinned(_ pinned: Bool, for serviceID: String) {
        updateSettings { $0.update(serviceID) { $0.isPinned = pinned } }
    }

    /// 隐藏：只影响首页卡片是否出现，服务仍在「设置 → 服务与接入」里，通知同步照旧。
    func setHidden(_ hidden: Bool, for serviceID: String) {
        updateSettings { $0.update(serviceID) { $0.isHidden = hidden } }
    }

    // MARK: - 体检

    func probeAll() {
        guard !isProbing else { return }
        isProbing = true
        let feeds = self.feeds
        let pairs: [(String, URL)] = ServiceCatalog.all.compactMap { service in
            guard let url = url(for: service) else { return nil }
            return (service.id, url)
        }
        for service in ServiceCatalog.all where url(for: service) == nil {
            health[service.id] = .notConfigured
        }

        Task {
            await withTaskGroup(of: (String, ServiceHealth).self) { group in
                for (id, url) in pairs {
                    group.addTask {
                        (id, await feeds.probe(url))
                    }
                }
                for await (id, result) in group {
                    health[id] = result
                }
            }
            isProbing = false
            let failures = health.values.filter { !$0.isUsable }.count
            toast = failures == 0 ? "全部服务可达" : "有 \(failures) 个服务不可达"
        }
    }

    func probe(_ service: ServiceDefinition) {
        guard let url = url(for: service) else {
            health[service.id] = .notConfigured
            return
        }
        let feeds = self.feeds
        health[service.id] = .unknown
        Task {
            let result = await feeds.probe(url)
            health[service.id] = result
        }
    }

    func health(for service: ServiceDefinition) -> ServiceHealth {
        if url(for: service) == nil { return .notConfigured }
        return health[service.id] ?? .unknown
    }

    // MARK: - 网站数据

    func clearWebsiteData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            Task { @MainActor in
                AppModel.shared.toast = "网站数据已清除，下次进入将重新缓存"
                AppModel.shared.appendLog("已清除 WKWebView 网站数据")
            }
        }
    }

    var websiteDataSizeDescription: String {
        "由系统管理"
    }

    // MARK: - 后台任务

    func scheduleBackgroundRefresh() {
        #if os(iOS)
        guard settings.backgroundRefreshEnabled else { return }
        BackgroundSync.schedule(after: 20 * 60)
        #endif
    }

    func performBackgroundSync() async {
        let targets = buildTargets()
        guard !targets.isEmpty else { return }
        let result = await engine.sync(targets: targets, isOnline: network.isOnline, lookbackHours: settings.lookbackHours)
        snapshot = result.snapshot
        lastReport = result.report
        scheduleBackgroundRefresh()
        appendLog("后台同步：\(result.report.summaryText)")
    }

    func persistOnBackground() {
        SettingsStorage.save(settings)
        scheduleBackgroundRefresh()
    }

    // MARK: - 日志

    func appendLog(_ message: String) {
        let stamp = Date().formatted(.dateTime.hour().minute().second())
        log.insert("[\(stamp)] \(message)", at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
    }

    func clearLog() {
        log.removeAll()
    }

    private static func describe(_ error: any Error) -> String {
        if let failure = error as? FeedClients.HTTPFailure {
            return failure.description
        }
        if let urlError = error as? URLError {
            return HealthClassifier.classify(
                errorCode: urlError.errorCode,
                description: urlError.localizedDescription
            ).title
        }
        return error.localizedDescription
    }

    var notificationStatusText: String {
        switch authorization {
        case .authorized: "已授权"
        case .provisional: "临时授权"
        case .ephemeral: "临时授权"
        case .denied: "已拒绝"
        case .notDetermined: "未申请"
        @unknown default: "未知"
        }
    }
}
