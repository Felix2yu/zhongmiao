import Foundation

struct DiarumDiary: Codable, Hashable, Sendable, Identifiable {
    var id: String?
    var date: String
    var content: String?
    var mood: Int?
    var tags: [String]?
    var exists: Bool?

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

struct DiarumSnapshot: Codable, Sendable {
    var today: DiarumDiary?
    var recent: [DiarumDiary]
    var stats: DiarumStats?
}
