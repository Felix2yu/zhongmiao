import Foundation

struct YuexiUpcoming: Codable, Hashable, Sendable {
    var name: String?
    var nextPeriod: String
    var daysLeft: Int

    enum CodingKeys: String, CodingKey {
        case name
        case nextPeriod = "next_period"
        case daysLeft = "days_left"
    }
}

struct YuexiNotificationConfig: Codable, Hashable, Sendable {
    var enabled: Bool?
    var daysBefore: Int?
    var lastNotified: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case daysBefore = "days_before"
        case lastNotified = "last_notified"
    }
}

struct YuexiNotificationStatus: Codable, Hashable, Sendable {
    var config: YuexiNotificationConfig?
    var upcoming: [YuexiUpcoming]

    private enum CodingKeys: String, CodingKey {
        case config, upcoming
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try container.decodeIfPresent(YuexiNotificationConfig.self, forKey: .config)
        // 服务端在没有预测时会返回 "upcoming": null。
        upcoming = try container.decodeIfPresent([YuexiUpcoming].self, forKey: .upcoming) ?? []
    }
}

struct YuexiAnomaly: Codable, Hashable, Sendable, Identifiable {
    var type: String
    var description: String
    var severity: String?

    var id: String { type + description }
}

struct YuexiSnapshot: Codable, Sendable {
    var status: YuexiNotificationStatus?
    var anomalies: [YuexiAnomaly]
}
