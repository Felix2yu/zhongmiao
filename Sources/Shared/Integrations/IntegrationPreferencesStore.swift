import Foundation
import ZhongmiaoCore

struct IntegrationPreference: Codable, Hashable, Sendable {

    var preferWeb: Bool
    var remindersEnabled: Bool
    /// 是否把同一批提醒写进系统日历与提醒事项。
    ///
    /// 默认关闭：写入的是用户自己的日历，属于有侵入性的操作，必须显式开启。
    /// 开启后与本地通知共用一份计划，但互不占预算——系统条目由系统持有，
    /// App 被杀、描述文件过期都照旧到点，适合生日、纪念日这类远期项。
    var systemRemindersEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    /// 牵丝约会默认提前天数。
    var eventLeadDays: Int
    var lastValidatedAt: Date?
    var credentialExpiresAt: Date?
    var lastAuthFailure: String?

    init(
        preferWeb: Bool = false,
        remindersEnabled: Bool = false,
        systemRemindersEnabled: Bool = false,
        reminderHour: Int = 9,
        reminderMinute: Int = 0,
        eventLeadDays: Int = 1,
        lastValidatedAt: Date? = nil,
        credentialExpiresAt: Date? = nil,
        lastAuthFailure: String? = nil
    ) {
        self.preferWeb = preferWeb
        self.remindersEnabled = remindersEnabled
        self.systemRemindersEnabled = systemRemindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.eventLeadDays = eventLeadDays
        self.lastValidatedAt = lastValidatedAt
        self.credentialExpiresAt = credentialExpiresAt
        self.lastAuthFailure = lastAuthFailure
    }

    private enum CodingKeys: String, CodingKey {
        case preferWeb, remindersEnabled, systemRemindersEnabled, reminderHour, reminderMinute, eventLeadDays
        case lastValidatedAt, credentialExpiresAt, lastAuthFailure
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferWeb = try container.decodeIfPresent(Bool.self, forKey: .preferWeb) ?? false
        remindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
        systemRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemRemindersEnabled) ?? false
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 9
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        eventLeadDays = try container.decodeIfPresent(Int.self, forKey: .eventLeadDays) ?? 1
        lastValidatedAt = try container.decodeIfPresent(Date.self, forKey: .lastValidatedAt)
        credentialExpiresAt = try container.decodeIfPresent(Date.self, forKey: .credentialExpiresAt)
        lastAuthFailure = try container.decodeIfPresent(String.self, forKey: .lastAuthFailure)
    }

    static func defaults(for serviceID: String) -> IntegrationPreference {
        let hour: Int
        switch serviceID {
        case "qingye": hour = 8
        case "diarum": hour = 21
        default: hour = 9
        }
        let supportsReminders = IntegrationCatalog.definition(for: serviceID)?.supportsReminders ?? false
        return IntegrationPreference(
            remindersEnabled: supportsReminders,
            reminderHour: hour,
            reminderMinute: 0,
            eventLeadDays: 1
        )
    }
}

struct IntegrationPreferences: Codable, Hashable, Sendable {

    var services: [String: IntegrationPreference]

    init(services: [String: IntegrationPreference] = [:]) {
        self.services = services
    }

    private enum CodingKeys: String, CodingKey {
        case services
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        services = try container.decodeIfPresent([String: IntegrationPreference].self, forKey: .services) ?? [:]
    }

    func preference(for serviceID: String) -> IntegrationPreference {
        services[serviceID] ?? .defaults(for: serviceID)
    }

    mutating func update(_ serviceID: String, _ transform: (inout IntegrationPreference) -> Void) {
        var value = services[serviceID] ?? .defaults(for: serviceID)
        transform(&value)
        services[serviceID] = value
    }
}

enum IntegrationPreferencesStore {

    static let key = "zhongmiao.integrations.v1"

    static func load() -> IntegrationPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(IntegrationPreferences.self, from: data) else {
            return IntegrationPreferences()
        }
        return decoded
    }

    static func save(_ preferences: IntegrationPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
