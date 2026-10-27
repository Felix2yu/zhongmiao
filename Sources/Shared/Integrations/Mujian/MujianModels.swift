import Foundation
import ZhongmiaoCore

struct MujianDashboard: Codable, Hashable, Sendable {
    var totalRecords: Int?
    var totalCost: Double?
    var avgRating: Double?
    var totalCities: Int?
    var byCategory: [MujianNameCount]?
    var byCity: [MujianNameCount]?
    var byMonth: [MujianNameCount]?
    var topRated: [MujianRecord]?
    var recentRecords: [MujianRecord]?

    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case totalCost = "total_cost"
        case avgRating = "avg_rating"
        case totalCities = "total_cities"
        case byCategory = "by_category"
        case byCity = "by_city"
        case byMonth = "by_month"
        case topRated = "top_rated"
        case recentRecords = "recent_records"
    }
}

/// 看板里的「名字 + 数量」条目。
///
/// 服务端三种统计用的键不一样：`by_category` / `by_city` 是 `name`，
/// `by_month` 是 `month`（形如 `2026-10`）。这里做兼容解码，缺字段不至于让整份看板解码失败。
struct MujianNameCount: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var count: Int

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, month, label, count
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = (try? container.decode(Int.self, forKey: .count)) ?? 0
        let candidates = [
            try? container.decode(String.self, forKey: .name),
            try? container.decode(String.self, forKey: .month),
            try? container.decode(String.self, forKey: .label)
        ]
        name = candidates.compactMap { $0 }.first { !$0.isEmpty } ?? "未分类"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(count, forKey: .count)
    }
}

/// 一场演出。字段与后端 `models.Record` 对齐，只取原生界面用得到的部分。
struct MujianRecord: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var city: String?
    var address: String?
    /// unix 秒；0 表示服务端也没记时间。
    var date: Int64?
    var dateText: String?
    var seat: String?
    var duration: Int?
    var rating: Int?
    var categoryNames: [String]?
    var artistNames: [String]?
    var remark: String?
    var watched: Bool?
    var activeStatus: Int?
    var price: Double?
    var cover: String?

    var startsAt: Date? {
        guard let date, date > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(date))
    }

    var categoryLabel: String {
        let names = (categoryNames ?? []).filter { !$0.isEmpty }
        return names.isEmpty ? "未分类" : names.joined(separator: " / ")
    }

    var venueLabel: String {
        [city, address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct MujianRecordList: Codable, Sendable {
    var records: [MujianRecord]
    var total: Int?

    enum CodingKeys: String, CodingKey {
        case records, total
    }
}

struct MujianCategory: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
}

struct MujianSnapshot: Codable, Sendable {
    var dashboard: MujianDashboard?
    var upcoming: [Show]
}
