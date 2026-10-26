import Foundation

/// 通知收件箱 + 游标账本。
///
/// 设计要点：
/// 1. **幂等合并**：同一事件重复到达（APNs 重投、ntfy 重放、补发扫描）只入库一次。
/// 2. **游标单调前进**：`since` 只会变大，避免断线重连后反复拉取历史。
/// 3. **容量有界**：超出上限时优先淘汰"已读且最旧"的记录，未读优先保留。
///
/// 纯值类型、无 I/O，便于单元测试。
public struct NotificationLedger: Codable, Sendable {

    public struct MergeResult: Sendable, Equatable {
        /// 真正新增、且尚未投递的条目（按时间升序，便于按序补发）。
        public let inserted: [NotificationItem]
        public let duplicateCount: Int

        public var isEmpty: Bool { inserted.isEmpty }
    }

    public private(set) var items: [NotificationItem]
    /// serviceID → 已同步到的时间点。
    public private(set) var cursors: [String: Date]
    /// 收件箱上限，超出后按策略淘汰。
    public var capacity: Int

    public init(items: [NotificationItem] = [], cursors: [String: Date] = [:], capacity: Int = 500) {
        self.items = items
        self.cursors = cursors
        self.capacity = max(50, capacity)
    }

    // MARK: - Codable（capacity 兼容旧数据）

    private enum CodingKeys: String, CodingKey {
        case items, cursors, capacity
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([NotificationItem].self, forKey: .items) ?? []
        cursors = try container.decodeIfPresent([String: Date].self, forKey: .cursors) ?? [:]
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity) ?? 500
    }

    // MARK: - 合并

    /// 合并一批新事件。返回值中的 `inserted` 只包含**首次出现且尚未投递**的条目。
    public mutating func merge(_ incoming: [NotificationItem], now: Date = Date()) -> MergeResult {
        var knownIDs = Set(items.map(\.id))
        var inserted: [NotificationItem] = []
        var duplicates = 0

        // 同一批里也可能自带重复，按时间升序处理保证补发顺序稳定。
        for item in incoming.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard !item.id.isEmpty else { continue }
            if knownIDs.contains(item.id) {
                duplicates += 1
                continue
            }
            knownIDs.insert(item.id)
            var stored = item
            stored.receivedAt = now
            if stored.deliveredAt != nil { stored.deliveredAt = nil }
            items.append(stored)
            inserted.append(stored)
        }

        if !inserted.isEmpty {
            items.sort { $0.createdAt > $1.createdAt }
            trimToCapacity()
        }
        return MergeResult(inserted: inserted, duplicateCount: duplicates)
    }

    /// 页面内桥接通知：命中同一去重键时视为重复，不重复弹窗。
    public mutating func merge(_ item: NotificationItem) -> Bool {
        !merge([item]).inserted.isEmpty
    }

    // MARK: - 投递状态

    /// 标记已投递。返回是否存在该条目。
    @discardableResult
    public mutating func markDelivered(id: String, at date: Date = Date()) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items[index].deliveredAt = date
        return true
    }

    /// 尚未投递的条目（断线期间积压），按时间升序。
    public var pendingDelivery: [NotificationItem] {
        items.filter { $0.deliveredAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - 已读

    public mutating func markRead(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
    }

    public mutating func markAllRead(serviceID: String? = nil) {
        for index in items.indices where serviceID == nil || items[index].serviceID == serviceID {
            items[index].isRead = true
        }
    }

    /// 把服务端广播的「已读」事件落到本地。
    ///
    /// 服务端把目标消息的 id 写进动作消息的 `sequence_id`；普通消息的 `sequence_id`
    /// 与消息 id 相同、JSON 里被省略，因此匹配时消息 id 也要认（见
    /// `NotificationItem.matchesNtfyTarget`）。
    /// - Returns: 本次真正从未读翻成已读的条数。
    @discardableResult
    public mutating func markRead(ntfyTargets: [String], serviceID: String) -> Int {
        guard !ntfyTargets.isEmpty else { return 0 }
        let targets = Set(ntfyTargets)
        var changed = 0
        for index in items.indices {
            guard items[index].serviceID == serviceID, !items[index].isRead else { continue }
            guard items[index].matchesNtfyTarget(targets) else { continue }
            items[index].isRead = true
            changed += 1
        }
        return changed
    }

    public var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    public func unreadCount(serviceID: String) -> Int {
        items.filter { !$0.isRead && $0.serviceID == serviceID }.count
    }

    // MARK: - 游标

    public func cursor(for serviceID: String) -> Date? {
        cursors[serviceID]
    }

    /// 游标只前进不后退；返回是否真的推进。
    @discardableResult
    public mutating func advanceCursor(serviceID: String, to date: Date) -> Bool {
        if let existing = cursors[serviceID], existing >= date { return false }
        cursors[serviceID] = date
        return true
    }

    /// 冷启动的拉取起点：有游标用游标，否则回看最近 `lookback`。
    public func fetchSince(serviceID: String, lookback: TimeInterval = 86_400, now: Date = Date()) -> Date {
        cursors[serviceID] ?? now.addingTimeInterval(-lookback)
    }

    // MARK: - 清理

    public mutating func remove(serviceID: String? = nil) {
        guard let serviceID else {
            items.removeAll()
            cursors.removeAll()
            return
        }
        items.removeAll { $0.serviceID == serviceID }
        cursors[serviceID] = nil
    }

    /// 删除单条。
    public mutating func remove(id: String) {
        items.removeAll { $0.id == id }
    }

    private mutating func trimToCapacity() {
        guard items.count > capacity else { return }
        var overflow = items.count - capacity
        // 第一轮：淘汰已读的最旧记录。
        var index = items.count - 1
        while overflow > 0, index >= 0 {
            if items[index].isRead {
                items.remove(at: index)
                overflow -= 1
            }
            index -= 1
        }
        // 第二轮：仍然超限时，从最旧开始淘汰未读。
        if overflow > 0 {
            items.removeLast(min(overflow, items.count))
        }
    }
}
