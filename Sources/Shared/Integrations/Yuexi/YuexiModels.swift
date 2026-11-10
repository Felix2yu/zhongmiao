import Foundation
import ZhongmiaoCore

/// 与页面共用同一份提醒计划。
///
/// 设置页改开关或时刻后，中心会直接从缓存里的快照重排；页面内的排程也走这里，
/// 两条路径不会生成不一样的计划。
extension YuexiSnapshot {

    func reminderPlans(hour: Int, minute: Int) -> [PlannedReminder] {
        guard let status else { return [] }
        let inputs: [YuexiReminderInput] = status.upcoming.compactMap { item in
            guard let date = QiansiLocalDate.parse(item.nextPeriod) else { return nil }
            return YuexiReminderInput(name: item.name ?? "月汐", nextPeriod: date, daysLeft: item.daysLeft)
        }
        return YuexiReminderPlanner.plan(
            upcoming: inputs,
            daysBefore: status.config?.daysBefore ?? 3,
            hour: hour,
            minute: minute
        )
    }
}

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
    /// 本月的记录与人员。新加的字段，旧缓存里没有时按空处理。
    var records: YuexiRecords?
}

/// 月汐里记录经期的人。
struct YuexiPerson: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var userId: Int64?
    var name: String
    var cycleLength: Int?
    var periodLength: Int?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userId = "user_id"
        case cycleLength = "cycle_length"
        case periodLength = "period_length"
        case createdAt = "created_at"
    }
}

/// 一次经期记录。end_date 为空表示还没结束。
struct YuexiRecord: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var personId: Int64
    var startDate: String
    var endDate: String?
    var effectiveEndDate: String?
    var note: String
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, note
        case personId = "person_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case effectiveEndDate = "effective_end_date"
        case createdAt = "created_at"
    }
}

/// 预测出来的区间（经期或排卵期）。
struct YuexiDateRange: Codable, Hashable, Sendable {
    var start: String
    var end: String
    var type: String
    var personId: Int64?

    enum CodingKeys: String, CodingKey {
        case start, end, type
        case personId = "person_id"
    }
}

/// /api/records 的完整返回。
struct YuexiRecords: Codable, Hashable, Sendable {
    var periods: [YuexiDateRange]
    var ovulations: [YuexiDateRange]
    var records: [YuexiRecord]
    var persons: [YuexiPerson]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        periods = try container.decodeIfPresent([YuexiDateRange].self, forKey: .periods) ?? []
        ovulations = try container.decodeIfPresent([YuexiDateRange].self, forKey: .ovulations) ?? []
        records = try container.decodeIfPresent([YuexiRecord].self, forKey: .records) ?? []
        persons = try container.decodeIfPresent([YuexiPerson].self, forKey: .persons) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case periods, ovulations, records, persons
    }
}
