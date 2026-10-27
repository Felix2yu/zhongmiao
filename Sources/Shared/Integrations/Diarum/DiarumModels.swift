import Foundation

struct DiarumDiary: Codable, Hashable, Sendable, Identifiable {
    var id: String?
    var date: String
    var content: String?
    var mood: Int?
    var tags: [String]?
    var exists: Bool?
    /// 服务端最后修改时间。编辑时用它判断「这一天在别处改过没有」。
    var updated: String?

    var identity: String { id ?? date }
    var hasContent: Bool {
        !(content ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct DiarumStats: Codable, Hashable, Sendable {
    var total: Int?
    var streak: Int?
}

struct DiarumRecentResponse: Codable, Sendable {
    var diaries: [DiarumDiary]
}

/// 搜索结果只带摘要，不带全文，点开再按日期取正文。
struct DiarumSearchHit: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var date: String
    var snippet: String?
    var mood: Int?
    var tags: [String]?

    var identity: String { id }
}

struct DiarumSearchResponse: Codable, Sendable {
    var results: [DiarumSearchHit]
    var total: Int?
}

struct DiarumSnapshot: Codable, Sendable {
    var today: DiarumDiary?
    var recent: [DiarumDiary]
    var stats: DiarumStats?
}
