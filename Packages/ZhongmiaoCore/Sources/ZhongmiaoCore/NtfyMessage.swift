import Foundation

/// ntfy 的 JSON 消息（`/{topic}/json` 与 `/{topic}/json?poll=1&since=...` 通用）。
///
/// 自托管 ntfy 既支持 SSE 实时流，也支持 `poll=1` 的一次性拉取 ——
/// 后者正是"重连后补发"的可靠通道：没有长连接也不会丢事件。
public struct NtfyMessage: Codable, Sendable, Equatable {
    public var id: String?
    public var time: Int?
    public var event: String?
    public var topic: String?
    public var message: String?
    public var title: String?
    public var priority: Int?
    public var tags: [String]?
    public var click: String?

    public init(
        id: String? = nil,
        time: Int? = nil,
        event: String? = nil,
        topic: String? = nil,
        message: String? = nil,
        title: String? = nil,
        priority: Int? = nil,
        tags: [String]? = nil,
        click: String? = nil
    ) {
        self.id = id
        self.time = time
        self.event = event
        self.topic = topic
        self.message = message
        self.title = title
        self.priority = priority
        self.tags = tags
        self.click = click
    }

    /// 是否为可投递的真实消息（过滤 open / keepalive / 空内容）。
    public var isDeliverable: Bool {
        let eventName = event ?? "message"
        guard eventName == "message" else { return false }
        let hasBody = !(message ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTitle = !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasBody || hasTitle
    }

    public func notificationItem(serviceID: String, fallbackURL: URL? = nil) -> NotificationItem? {
        guard isDeliverable else { return nil }
        let rawTime = time.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
        let resolvedTitle = (title?.isEmpty == false ? title! : (topic ?? "通知"))
        let resolvedBody = message ?? ""
        let link = click.flatMap(URL.init(string:)) ?? fallbackURL
        let identifier = NotificationItem.makeID(
            serviceID: serviceID,
            eventID: id,
            title: resolvedTitle,
            body: resolvedBody,
            createdAt: rawTime
        )
        return NotificationItem(
            id: identifier,
            serviceID: serviceID,
            title: resolvedTitle,
            body: resolvedBody,
            createdAt: rawTime,
            url: link,
            priority: .fromNtfy(priority),
            source: .ntfy
        )
    }
}

/// 逐行解析 ntfy 的 NDJSON 流，保留未完成的尾部。
public enum NtfyStreamDecoder {

    public static func decode(line: String) -> NtfyMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NtfyMessage.self, from: data)
    }

    /// 从缓冲区中取出完整行并解析，剩余半行留在 `buffer` 里。
    public static func drain(buffer: inout String) -> [NtfyMessage] {
        var messages: [NtfyMessage] = []
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newline])
            buffer = String(buffer[buffer.index(after: newline)...])
            if let message = decode(line: line) {
                messages.append(message)
            }
        }
        // 防御：单行超长（可能对端不是 NDJSON），丢弃避免内存膨胀。
        if buffer.count > 1_048_576 {
            buffer = ""
        }
        return messages
    }

    /// 把游标时间格式化成 ntfy 的 `since` 参数（unix 秒，向上取整避免漏事件）。
    public static func sinceParameter(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970.rounded(.down)))
    }
}
