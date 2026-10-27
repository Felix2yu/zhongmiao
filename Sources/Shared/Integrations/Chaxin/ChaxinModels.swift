import Foundation

struct ChaxinRepo: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var fullName: String
    var description: String?
    var language: String?
    var stargazersCount: Int?
    var monitored: Bool?
    var latestTag: String?
    var latestReleaseAt: String?
    var lastCheckedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, language, monitored
        case fullName = "full_name"
        case stargazersCount = "stargazers_count"
        case latestTag = "latest_tag"
        case latestReleaseAt = "latest_release_at"
        case lastCheckedAt = "last_checked_at"
    }
}

struct ChaxinNotification: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var repoId: Int64?
    var fullName: String?
    var tag: String?
    var releaseUrl: String?
    var releaseBody: String?
    var releasedAt: String?
    var sentAt: String?
    var status: String?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case id, tag, status, error
        case repoId = "repo_id"
        case fullName = "full_name"
        case releaseUrl = "release_url"
        case releaseBody = "release_body"
        case releasedAt = "released_at"
        case sentAt = "sent_at"
    }
}

struct ChaxinSnapshot: Codable, Sendable {
    var repos: [ChaxinRepo]
    var notifications: [ChaxinNotification]
}

/// 添加仓库的返回值：只回一个规范名。
struct ChaxinAddedRepo: Codable, Sendable {
    var fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

enum ChaxinDate {

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// 后端的零值时间是 `0001-01-01T00:00:00Z`，要按“无”处理。
    static func display(_ raw: String?, style: Date.FormatStyle = .dateTime.month().day().hour().minute()) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let date = fractional.date(from: raw) ?? plain.date(from: raw) else {
            return raw
        }
        let year = Calendar.current.component(.year, from: date)
        guard year > 1 else { return nil }
        return date.formatted(style)
    }
}
