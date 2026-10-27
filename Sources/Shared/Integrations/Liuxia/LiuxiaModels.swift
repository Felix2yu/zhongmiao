import Foundation
import ZhongmiaoCore

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

    var kind: LiuxiaEvent.Kind {
        eventType == "morning" ? .morning : .evening
    }

    var eventTitle: String { kind.title }

    var asEvent: LiuxiaEvent {
        LiuxiaEvent(
            city: city,
            date: date,
            time: time,
            kind: kind,
            quality: quality,
            aod: aod,
            model: model
        )
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

    var asEvent: LiuxiaEvent {
        LiuxiaEvent(
            city: city,
            date: date,
            time: time,
            kind: eventType == "morning" ? .morning : .evening,
            quality: quality,
            aod: aod,
            model: model
        )
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
    /// 未来一周的高质量场次（服务端按质量取前 N 条）。
    var rankings: LiuxiaRankings?

    /// 服务端给的「今天」。缓存跨天后要重取，否则今明会被标错。
    var cachedDay: String? { today?.today }
}
