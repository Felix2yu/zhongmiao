import Foundation

struct BiliDailyCount: Codable, Hashable, Sendable {
    var totalCount: Int?
    var totalWatchSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case totalWatchSeconds = "total_watch_seconds"
    }
}

struct BiliHistoryRecord: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var title: String
    var authorName: String?
    var viewAt: Int64?
    var duration: Int?
    var progress: Double?
    var cover: String?
    var viewTime: String?
    var isFinish: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, progress, cover
        case authorName = "author_name"
        case viewAt = "view_at"
        case viewTime = "view_time"
        case isFinish = "is_finish"
    }

    var watchedDate: Date? {
        viewAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var isCompleted: Bool { progress == -1 || isFinish == 1 }
}

struct BiliHistoryPageData: Codable, Sendable {
    var records: [BiliHistoryRecord]
    var total: Int64?
}

/// 主分类。后端返回 [{name, image}]（注意字段是 name，不是 main_category）。
struct BiliMainCategory: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var image: String?

    var id: String { name }
}

struct BiliHistoryEnvelope<T: Decodable>: Decodable {
    var status: String?
    var data: T?
}

struct BiliTagCount: Codable, Hashable, Sendable {
    var tagName: String?
    var count: Int?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case count
    }
}

struct BiliMonthlyStats: Codable, Hashable, Sendable {
    var year: Int?
    var totalVideos: Int?
    var totalDuration: Int?
    var uniqueAuthors: Int?
    var tagRanking: [BiliTagCount]?

    enum CodingKeys: String, CodingKey {
        case year
        case totalVideos = "total_videos"
        case totalDuration = "total_duration"
        case uniqueAuthors = "unique_authors"
        case tagRanking = "tag_ranking"
    }
}

struct BiliHistorySnapshot: Codable, Sendable {
    var daily: BiliDailyCount?
    var records: [BiliHistoryRecord]
    var monthly: BiliMonthlyStats?
}
