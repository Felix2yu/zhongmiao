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
    var toast: String?
    /// 通知点击 / 系统深链请求打开的服务页。
    var pendingRoute: Route?

    let network = NetworkMonitor()

    private let scheduler: NotificationScheduler
    private let engine: NotificationEngine
    private let feeds = FeedClients()
    private var notificationDelegate: NotificationDelegate?
    private var observers: [NSObjectProtocol] = []
    private var hasActivated = false

    // MARK: - 页面路由

    struct Route: Hashable, Identifiable {
        var serviceID: String
        var url: URL?

        var id: String { "\(serviceID)#\(url?.absoluteString ?? "root")" }

        init(serviceID: String, url: URL? = nil) {
            self.serviceID = serviceID
            self.url = url
        }
    }

    // MARK: - 初始化

    private init() {
        let settings = SettingsStorage.load()
        self.settings = settings
        self.ntfyTopics = NtfySubscriptionStore.load()
        let scheduler = NotificationScheduler()
        self.scheduler = scheduler
        self.engine = NotificationEngine(scheduler: scheduler, capacity: settings.inboxCapacity)
    }

    /// 由 AppDelegate 调用：注册通知代理、启动网络监听。必须早于页面加载。
    func activate() {
        guard !hasActivated else { return }
        hasActivated = true

        scheduler.registerCategories()

        let delegate = NotificationDelegate { serviceID, urlString in
            Task { @MainActor in
                AppModel.shared.handleNotificationOpen(serviceID: serviceID, urlString: urlString)
            }
        }
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
    }

    // MARK: - 地址解析

    func url(for service: ServiceDefinition) -> URL? {
        ServiceURLResolver.url(
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

    func resolvedNtfyBase() -> URL? {
        let override = settings.ntfyBaseURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            let normalized = override.contains("://") ? override : "https://" + override
            return URL(string: normalized)
        }
        guard let service = ServiceCatalog.service(id: "ntfy") else { return nil }
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
            return .success(try await feeds.fetchNtfyTopics(base: base))
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
                    relayURL: useRelay ? relay : nil,
                    relaySecret: settings.relaySecret
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
        let secret = settings.relaySecret
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

    private func handleNotificationOpen(serviceID: String, urlString: String?) {
        // 独立订阅的主题没有应用页，统一落到 ntfy。
        let routeID = ServiceDisplay.routeServiceID(for: serviceID)
        guard ServiceCatalog.service(id: routeID) != nil else { return }
        let url = urlString.flatMap { raw -> URL? in
            guard !raw.isEmpty else { return nil }
            return URL(string: raw)
        }
        pendingRoute = Route(serviceID: routeID, url: url)
        appendLog("打开通知：\(routeID)")
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
        Task { snapshot = await engine.markRead(id: item.id) }
    }

    func markAllRead(serviceID: String? = nil) {
        Task { snapshot = await engine.markAllRead(serviceID: serviceID) }
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
