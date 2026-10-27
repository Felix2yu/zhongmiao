import Foundation
import ZhongmiaoCore

/// 单个服务的用户级偏好（覆盖内置注册表）。
struct ServicePreference: Codable, Hashable, Sendable {
    /// 绝对地址覆盖，优先级最高。
    var urlOverride: String?
    /// 是否纳入通知同步的目标集合。前台同步、重连补拉、后台刷新都受它约束，
    /// 关掉即完全不向该服务发起通知请求。
    var notificationsEnabled: Bool
    /// ntfy 主题（为空表示该服务不通过 ntfy 投递）。
    var ntfyTopic: String?
    /// 通用通知流路径，例如 `/api/notifications`。
    var feedPath: String?
    /// 是否在首页置顶（排在所属分类最前）。
    var isPinned: Bool
    /// 是否在首页隐藏。只影响首页卡片，不改动通知同步与地址解析；
    /// 「设置 → 服务与接入」里始终可见，那是恢复入口。
    var isHidden: Bool

    private enum CodingKeys: String, CodingKey {
        case urlOverride, notificationsEnabled, ntfyTopic, feedPath, isPinned, isHidden
    }

    init(
        urlOverride: String? = nil,
        notificationsEnabled: Bool = false,
        ntfyTopic: String? = nil,
        feedPath: String? = nil,
        isPinned: Bool = false,
        isHidden: Bool = false
    ) {
        self.urlOverride = urlOverride
        self.notificationsEnabled = notificationsEnabled
        self.ntfyTopic = ntfyTopic
        self.feedPath = feedPath
        self.isPinned = isPinned
        self.isHidden = isHidden
    }

    /// 逐字段解码。`isHidden` 是后加的字段，旧偏好里没有这个键；合成的 Codable
    /// 遇到缺失的非可选 Bool 会抛 `keyNotFound`，进而让整个
    /// `[String: ServicePreference]` 解码失败、全部设置被重置，所以必须兜底。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        urlOverride = try container.decodeIfPresent(String.self, forKey: .urlOverride)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        ntfyTopic = try container.decodeIfPresent(String.self, forKey: .ntfyTopic)
        feedPath = try container.decodeIfPresent(String.self, forKey: .feedPath)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    /// 以注册表默认值初始化。
    static func `default`(for service: ServiceDefinition) -> ServicePreference {
        ServicePreference(
            notificationsEnabled: service.notificationsEnabledByDefault,
            ntfyTopic: service.ntfyTopic,
            feedPath: service.notificationFeedPath
        )
    }
}

/// 全局设置。整体 Codable，存 UserDefaults。
struct AppSettings: Codable, Hashable, Sendable {
    var addressing: AddressSettings
    var servicePreferences: [String: ServicePreference]
    /// 可选：自建推送中继地址（见 server/push-relay）。
    var relayURL: String
    /// ntfy 服务地址覆盖（默认取注册表里 ntfy 的解析结果）。
    var ntfyBaseURLOverride: String
    /// 后台刷新开关。
    var backgroundRefreshEnabled: Bool
    /// 冷启动回看窗口（小时）。
    var lookbackHours: Int
    /// 收件箱容量。
    var inboxCapacity: Int
    /// 是否在服务卡片上显示「离线可用」等能力标签。
    ///
    /// 默认开启；关掉后卡片只保留「未配置」这类真正需要处理的告警。
    var showServiceCapabilityTags: Bool

    /// 站外链接是否留在应用内打开。
    ///
    /// 默认开启：网页里点到外部链接（例如某个项目的官网、第三方文档）仍在应用内加载，
    /// 想出去用浏览器时走页面右上角/菜单里的「在浏览器打开」。
    /// `tel:`、`mailto:` 这类非网页协议始终交给系统。
    var keepExternalLinksInApp: Bool

    // MARK: 演出提醒

    /// 演出提醒总开关。关掉后不再拉幕间演出、不再排通知、不再开岛。
    var showsEnabled: Bool
    /// 本地通知提前量（小时）。默认 4 小时：午场 13–14 点开演落在上午提醒，
    /// 夜场 19–19:30 开演落在下班前提醒。
    var showsReminderLeadHours: Int
    /// 灵动岛提前量（小时）。默认贴着系统上限 8 小时——岛的触发时刻由快捷指令
    /// 或「打开 App」决定，窗口开得越大越容易被命中。
    var showsIslandLeadHours: Int
    /// 是否从幕间 API 拉取演出。
    var showsUseMujianAPI: Bool
    /// 是否从系统日历读取演出（幕间 CalDAV 同步过去的事件）。
    var showsUseCalendar: Bool
    /// 日历兜底的额外关键词，逗号分隔。
    ///
    /// 默认只认幕间同步过去的事件（UID 带 `@mujian`）。要连「在日历里自己建的演出」
    /// 也一起收，就在这里填关键词（匹配事件标题或日历名称），否则把工作会议也当成演出。
    var showsCalendarKeywords: String

    init(
        addressing: AddressSettings = .default,
        servicePreferences: [String: ServicePreference] = [:],
        relayURL: String = "",
        ntfyBaseURLOverride: String = "",
        backgroundRefreshEnabled: Bool = true,
        lookbackHours: Int = 24,
        inboxCapacity: Int = 500,
        showServiceCapabilityTags: Bool = true,
        keepExternalLinksInApp: Bool = true,
        showsEnabled: Bool = true,
        showsReminderLeadHours: Int = 4,
        showsIslandLeadHours: Int = 8,
        showsUseMujianAPI: Bool = true,
        showsUseCalendar: Bool = true,
        showsCalendarKeywords: String = ""
    ) {
        self.addressing = addressing
        self.servicePreferences = servicePreferences
        self.relayURL = relayURL
        self.ntfyBaseURLOverride = ntfyBaseURLOverride
        self.backgroundRefreshEnabled = backgroundRefreshEnabled
        self.lookbackHours = lookbackHours
        self.inboxCapacity = inboxCapacity
        self.showServiceCapabilityTags = showServiceCapabilityTags
        self.keepExternalLinksInApp = keepExternalLinksInApp
        self.showsEnabled = showsEnabled
        self.showsReminderLeadHours = showsReminderLeadHours
        self.showsIslandLeadHours = showsIslandLeadHours
        self.showsUseMujianAPI = showsUseMujianAPI
        self.showsUseCalendar = showsUseCalendar
        self.showsCalendarKeywords = showsCalendarKeywords
    }

    private enum CodingKeys: String, CodingKey {
        case addressing, servicePreferences, relayURL
        case ntfyBaseURLOverride, backgroundRefreshEnabled, lookbackHours, inboxCapacity
        case showServiceCapabilityTags
        case keepExternalLinksInApp
        case showsEnabled, showsReminderLeadHours, showsIslandLeadHours
        case showsUseMujianAPI, showsUseCalendar, showsCalendarKeywords
    }

    /// 逐字段解码，新增字段缺失时回落到默认值 —— 旧版本存下的设置不能因为
    /// 多了 `ntfyToken` 就整份解码失败。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addressing = try container.decodeIfPresent(AddressSettings.self, forKey: .addressing) ?? .default
        servicePreferences = try container.decodeIfPresent([String: ServicePreference].self, forKey: .servicePreferences) ?? [:]
        relayURL = try container.decodeIfPresent(String.self, forKey: .relayURL) ?? ""
        ntfyBaseURLOverride = try container.decodeIfPresent(String.self, forKey: .ntfyBaseURLOverride) ?? ""
        backgroundRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .backgroundRefreshEnabled) ?? true
        lookbackHours = try container.decodeIfPresent(Int.self, forKey: .lookbackHours) ?? 24
        inboxCapacity = try container.decodeIfPresent(Int.self, forKey: .inboxCapacity) ?? 500
        showServiceCapabilityTags = try container.decodeIfPresent(Bool.self, forKey: .showServiceCapabilityTags) ?? true
        keepExternalLinksInApp = try container.decodeIfPresent(Bool.self, forKey: .keepExternalLinksInApp) ?? true
        showsEnabled = try container.decodeIfPresent(Bool.self, forKey: .showsEnabled) ?? true
        showsReminderLeadHours = try container.decodeIfPresent(Int.self, forKey: .showsReminderLeadHours) ?? 4
        showsIslandLeadHours = try container.decodeIfPresent(Int.self, forKey: .showsIslandLeadHours) ?? 8
        showsUseMujianAPI = try container.decodeIfPresent(Bool.self, forKey: .showsUseMujianAPI) ?? true
        showsUseCalendar = try container.decodeIfPresent(Bool.self, forKey: .showsUseCalendar) ?? true
        showsCalendarKeywords = try container.decodeIfPresent(String.self, forKey: .showsCalendarKeywords) ?? ""
    }

    // MARK: 演出提醒派生值

    var showsReminderLead: TimeInterval {
        TimeInterval(max(0, showsReminderLeadHours)) * 3600
    }

    /// 岛的提前量按系统上限夹住：设置里允许填更大值，但超出 8 小时的部分没有意义。
    var showsIslandLead: TimeInterval {
        ShowReminder.clampedIslandLead(TimeInterval(max(0, showsIslandLeadHours)) * 3600)
    }

    /// 日历兜底的关键词，去掉空串与首尾空格。
    var showsCalendarKeywordList: [String] {
        showsCalendarKeywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func preference(for service: ServiceDefinition) -> ServicePreference {
        servicePreferences[service.id] ?? .default(for: service)
    }

    mutating func update(_ serviceID: String, _ transform: (inout ServicePreference) -> Void) {
        let service = ServiceCatalog.service(id: serviceID)
        var current = servicePreferences[serviceID]
            ?? service.map(ServicePreference.default(for:))
            ?? ServicePreference()
        transform(&current)
        servicePreferences[serviceID] = current
    }

    /// 通知是否真的能产生数据：要么有 feed，要么有 ntfy 主题，要么配了中继。
    func hasNotificationChannel(for service: ServiceDefinition) -> Bool {
        let pref = preference(for: service)
        if !pref.notificationsEnabled { return false }
        let hasFeed = !(pref.feedPath ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let hasTopic = !(pref.ntfyTopic ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let hasRelay = !relayURL.trimmingCharacters(in: .whitespaces).isEmpty
        return hasFeed || hasTopic || (hasRelay && service.kind != .utility)
    }
}

enum SettingsStorage {
    static let userDefaultsKey = "zhongmiao.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
}
