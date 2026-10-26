import Foundation
import ZhongmiaoCore

/// 单个服务的用户级偏好（覆盖内置注册表）。
struct ServicePreference: Codable, Hashable, Sendable {
    /// 绝对地址覆盖，优先级最高。
    var urlOverride: String?
    /// 是否参与后台通知同步。
    var notificationsEnabled: Bool
    /// ntfy 主题（为空表示该服务不通过 ntfy 投递）。
    var ntfyTopic: String?
    /// 通用通知流路径，例如 `/api/notifications`。
    var feedPath: String?
    var isPinned: Bool

    init(
        urlOverride: String? = nil,
        notificationsEnabled: Bool = false,
        ntfyTopic: String? = nil,
        feedPath: String? = nil,
        isPinned: Bool = false
    ) {
        self.urlOverride = urlOverride
        self.notificationsEnabled = notificationsEnabled
        self.ntfyTopic = ntfyTopic
        self.feedPath = feedPath
        self.isPinned = isPinned
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
    /// 中继共享密钥，随请求头发送。
    var relaySecret: String
    /// ntfy 服务地址覆盖（默认取注册表里 ntfy 的解析结果）。
    var ntfyBaseURLOverride: String
    /// 后台刷新开关。
    var backgroundRefreshEnabled: Bool
    /// 冷启动回看窗口（小时）。
    var lookbackHours: Int
    /// 收件箱容量。
    var inboxCapacity: Int

    init(
        addressing: AddressSettings = .default,
        servicePreferences: [String: ServicePreference] = [:],
        relayURL: String = "",
        relaySecret: String = "",
        ntfyBaseURLOverride: String = "",
        backgroundRefreshEnabled: Bool = true,
        lookbackHours: Int = 24,
        inboxCapacity: Int = 500
    ) {
        self.addressing = addressing
        self.servicePreferences = servicePreferences
        self.relayURL = relayURL
        self.relaySecret = relaySecret
        self.ntfyBaseURLOverride = ntfyBaseURLOverride
        self.backgroundRefreshEnabled = backgroundRefreshEnabled
        self.lookbackHours = lookbackHours
        self.inboxCapacity = inboxCapacity
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
    private static let key = "zhongmiao.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
