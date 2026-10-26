import Foundation

/// 统一的通知条目。来源可以是 APNs、ntfy、应用自带 JSON 流，或 WebView 内页面调用。
public struct NotificationItem: Codable, Identifiable, Hashable, Sendable {

    public enum Priority: String, Codable, Sendable, CaseIterable {
        /// 静默：仅入收件箱，不打断。
        case passive
        /// 常规提醒。
        case active
        /// 时效性：可突破专注模式（需要 Time Sensitive 权限）。
        case timeSensitive

        /// 映射到 ntfy 的 1–5 优先级。
        public static func fromNtfy(_ value: Int?) -> Priority {
            switch value ?? 3 {
            case ...2: .passive
            case 3: .active
            default: .timeSensitive
            }
        }
    }

    public enum Source: String, Codable, Sendable {
        case apns
        case ntfy
        case feed
        /// 页面内 `Notification` / `showNotification` 被原生桥接管。
        case web
        /// 断线补发时补偿的历史事件。
        case replay
    }

    /// 去重键。跨来源、跨重启都必须稳定。
    public var id: String
    /// 归属服务 id，用于筛选与深链。
    public var serviceID: String
    public var title: String
    public var body: String
    /// 事件发生时间（服务端时间优先）。
    public var createdAt: Date
    /// 点击后要打开的页面。
    public var url: URL?
    public var priority: Priority
    public var source: Source
    public var isRead: Bool
    /// 本地通知是否已投递；nil 表示尚未投递（断线排队中）。
    public var deliveredAt: Date?
    /// 原生侧首次拿到这条记录的时间。
    public var receivedAt: Date
    /// ntfy 的消息 id（服务端 `id`）。标记已读时用它和服务器上的消息对上。
    public var ntfyMessageID: String?
    /// ntfy 的序列 id（服务端 `sequence_id`）。普通消息通常被服务端省略，此时用消息 id 兜底。
    public var ntfySequenceID: String?
    /// 消息所在的 ntfy 主题。标记已读的请求要发回这个主题。
    public var ntfyTopic: String?

    public init(
        id: String,
        serviceID: String,
        title: String,
        body: String,
        createdAt: Date,
        url: URL? = nil,
        priority: Priority = .active,
        source: Source = .feed,
        isRead: Bool = false,
        deliveredAt: Date? = nil,
        receivedAt: Date = Date(),
        ntfyMessageID: String? = nil,
        ntfySequenceID: String? = nil,
        ntfyTopic: String? = nil
    ) {
        self.id = id
        self.serviceID = serviceID
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.url = url
        self.priority = priority
        self.source = source
        self.isRead = isRead
        self.deliveredAt = deliveredAt
        self.receivedAt = receivedAt
        self.ntfyMessageID = ntfyMessageID
        self.ntfySequenceID = ntfySequenceID
        self.ntfyTopic = ntfyTopic
    }

    /// 是否命中服务端广播的已读目标。
    ///
    /// 服务端用 `sequence_id` 寻址目标消息；而普通消息的 `sequence_id` 与消息 id 相同、
    /// 在 JSON 里被省略，所以消息 id 也要认。
    public func matchesNtfyTarget(_ targets: Set<String>) -> Bool {
        if let sequenceID = ntfySequenceID, targets.contains(sequenceID) { return true }
        if let messageID = ntfyMessageID, targets.contains(messageID) { return true }
        return false
    }

    /// 标记已读请求要用的目标 id：优先序列 id，其次消息 id。
    public var ntfyTargetID: String? {
        NtfyActionID.targetID(sequenceID: ntfySequenceID, messageID: ntfyMessageID)
    }

    /// 生成稳定去重键：优先使用服务端事件 id，否则用内容指纹。
    ///
    /// 注意：**不能用 `String.hashValue`**——Swift 的哈希随机化会让同一内容在
    /// 不同进程得到不同值，进程重启后去重就会失效，导致历史通知被重复弹窗。
    /// 这里改用 FNV-1a（跨进程稳定）。
    public static func makeID(serviceID: String, eventID: String?, title: String, body: String, createdAt: Date) -> String {
        if let eventID, !eventID.isEmpty {
            return "\(serviceID)#\(eventID)"
        }
        let stamp = Int(createdAt.timeIntervalSince1970)
        let fingerprint = stableHash("\(title)\u{1F}\(body)")
        return "\(serviceID)#\(stamp)#\(fingerprint)"
    }

    /// FNV-1a 64 位，跨进程稳定。
    static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
