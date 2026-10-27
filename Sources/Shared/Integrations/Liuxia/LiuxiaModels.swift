import Foundation

struct LiuxiaRecord: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var city: String
    var date: String
    var time: String?
    var eventType: String
    var model: String
    var quality: Double?
    var aod: Double?

    enum CodingKeys: String, CodingKey {
        case id, city, date, time, model, quality, aod
        case eventType = "event_type"
    }

    var eventTitle: String {
        eventType == "morning" ? "朝霞" : "晚霞"
    }
}

struct LiuxiaToday: Codable, Hashable, Sendable {
    var today: String
    var tomorrow: String
    var data: [LiuxiaRecord]
}

struct LiuxiaDateRanking: Codable, Hashable, Sendable, Identifiable {
    var date: String
    var city: String
    var time: String?
    var eventType: String
    var model: String
    var quality: Double?
    var aod: Double?

    var id: String { "\(date)-\(city)-\(eventType)-\(model)" }

    enum CodingKeys: String, CodingKey {
        case date, city, time, model, quality, aod
        case eventType = "event_type"
    }
}

struct LiuxiaRankings: Codable, Sendable {
    var bestDates: [LiuxiaDateRanking]

    enum CodingKeys: String, CodingKey {
        case bestDates = "best_dates"
    }
}

struct LiuxiaSnapshot: Codable, Sendable {
    var today: LiuxiaToday?
    var cities: [String]
    var rankings: LiuxiaRankings?
}
