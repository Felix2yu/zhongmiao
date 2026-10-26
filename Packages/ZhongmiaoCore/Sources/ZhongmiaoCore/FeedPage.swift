import Foundation

/// 可解析多种时间表示（ISO8601 带/不带毫秒、unix 秒/毫秒、常见 SQL 格式）。
public struct FlexibleDate: Codable, Hashable, Sendable {
    public var date: Date

    public init(_ date: Date) { self.date = date }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            // 13 位视为毫秒。
            self.date = seconds > 100_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1000)
                : Date(timeIntervalSince1970: seconds)
            return
        }
        let raw = try container.decode(String.self)
        guard let parsed = FlexibleDate.parse(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析时间：\(raw)")
        }
        self.date = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(FlexibleDate.iso8601.string(from: date))
    }

    /// 线程安全：Foundation 的格式化器在读取场景下可共享。
    nonisolated(unsafe) public static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let sqlFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    public static func parse(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = iso8601.date(from: trimmed) { return date }
        if let date = iso8601NoFraction.date(from: trimmed) { return date }
        if let date = sqlFormatter.date(from: trimmed) { return date }
        if let seconds = Double(trimmed) {
            return seconds > 100_000_000_000
                ? Date(timeIntervalSince1970: seconds / 1000)
                : Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}

/// 通用通知流契约（各 Go 应用可选实现）：
///
/// ```json
/// {
///   "items": [
///     { "id": "evt_123", "title": "构建完成", "body": "…",
///       "createdAt": "2026-10-24T05:00:00Z", "url": "/tasks/42", "priority": "active" }
///   ],
///   "nextCursor": "2026-10-24T05:00:00Z"
/// }
/// ```
///
/// 请求参数：`?since=<ISO8601>&limit=50`。服务端按 `createdAt` 升序返回。
public struct FeedPage: Decodable, Sendable {
    public var items: [FeedEntry]
    public var nextCursor: String?

    public init(items: [FeedEntry], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

public struct FeedEntry: Decodable, Sendable {
    public var id: String?
    public var title: String
    public var body: String?
    public var createdAt: FlexibleDate?
    public var url: String?
    public var priority: String?

    public init(
        id: String? = nil,
        title: String,
        body: String? = nil,
        createdAt: Date? = nil,
        url: String? = nil,
        priority: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt.map(FlexibleDate.init)
        self.url = url
        self.priority = priority
    }

    func notificationItem(serviceID: String, baseURL: URL?, fallbackDate: Date) -> NotificationItem? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let body = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt = createdAt?.date ?? fallbackDate
        let link: URL? = {
            guard let raw = url, !raw.isEmpty else { return nil }
            if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
            guard let baseURL else { return nil }
            return URL(string: raw, relativeTo: baseURL)?.absoluteURL
        }()
        return NotificationItem(
            id: NotificationItem.makeID(
                serviceID: serviceID,
                eventID: id,
                title: title,
                body: body,
                createdAt: createdAt
            ),
            serviceID: serviceID,
            title: title,
            body: body,
            createdAt: createdAt,
            url: link,
            priority: FeedEntry.priority(from: priority),
            source: .feed
        )
    }

    static func priority(from raw: String?) -> NotificationItem.Priority {
        switch raw?.lowercased() {
        case "passive", "low", "min": .passive
        case "time-sensitive", "timesensitive", "urgent", "high": .timeSensitive
        default: .active
        }
    }
}

public enum FeedParser {
    public static func decode(_ data: Data) throws -> FeedPage {
        let decoder = JSONDecoder()
        return try decoder.decode(FeedPage.self, from: data)
    }

    /// 把一页数据转换为统一通知条目。
    public static func items(
        from page: FeedPage,
        serviceID: String,
        baseURL: URL?,
        now: Date = Date()
    ) -> [NotificationItem] {
        page.items.compactMap { $0.notificationItem(serviceID: serviceID, baseURL: baseURL, fallbackDate: now) }
    }
}
