import Foundation

/// 演出缓存。
///
/// 它是主 App、`LiveActivityIntent` 与通知排程之间交换数据的唯一载体：
/// Intent 被系统在后台拉起时既不能联网等待、也不该重新鉴权，只能读本地缓存。
/// 所以「刷新时机」与「读取时机」必须彻底分离——刷新在前台做，读取在任何时候都能做。
///
/// 字段新增一律用 `decodeIfPresent` 兜底：缓存解码失败等于清空用户已排好的全部提醒。
public struct ShowLibrary: Codable, Sendable, Equatable {

    public var items: [Show]
    /// 幕间 API 最近一次成功刷新的时刻。
    public var lastAPIFetchAt: Date?
    /// 系统日历最近一次成功读取的时刻。
    public var lastCalendarFetchAt: Date?

    public static let empty = ShowLibrary()

    public init(
        items: [Show] = [],
        lastAPIFetchAt: Date? = nil,
        lastCalendarFetchAt: Date? = nil
    ) {
        self.items = items
        self.lastAPIFetchAt = lastAPIFetchAt
        self.lastCalendarFetchAt = lastCalendarFetchAt
    }

    private enum CodingKeys: String, CodingKey {
        case items, lastAPIFetchAt, lastCalendarFetchAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Show].self, forKey: .items) ?? []
        lastAPIFetchAt = try container.decodeIfPresent(Date.self, forKey: .lastAPIFetchAt)
        lastCalendarFetchAt = try container.decodeIfPresent(Date.self, forKey: .lastCalendarFetchAt)
    }

    // MARK: - 查询

    /// 尚未散场的演出，按开演时间升序。
    public func upcoming(now: Date = .now) -> [Show] {
        items
            .filter { $0.phase(now: now) != .ended }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// 最近一场尚未开演的演出。
    public func next(now: Date = .now) -> Show? {
        upcoming(now: now).first { $0.startsAt > now }
    }

    /// 此刻该把灵动岛亮起来的那一场。
    ///
    /// 取**最近**一场命中窗口的，而不是窗口内任意一场：一天的午场与夜场可能同时落在
    /// 8 小时窗口里，若挑错就会给九小时后的夜场开岛、却在午场开演时挂着错的剧名。
    public func showForIsland(
        now: Date = .now,
        lead: TimeInterval = ShowReminder.defaultIslandLead
    ) -> Show? {
        upcoming(now: now).first { $0.shouldStartIsland(now: now, lead: lead) }
    }

    // MARK: - 写入

    /// 合入一批演出。
    ///
    /// 同一场演出很可能同时来自两个数据源（幕间 API，以及它同步进系统日历的 CalDAV 事件），
    /// 必须并成一条——否则会排两条通知、开两个岛。
    ///
    /// - Returns: 新增的场次数（供 UI 提示「发现 N 场新演出」）。
    @discardableResult
    public mutating func merge(_ incoming: [Show]) -> Int {
        var result = items
        var added = 0

        for show in incoming {
            guard let index = result.firstIndex(where: { $0.isSameShow(as: show) }) else {
                result.append(show)
                added += 1
                continue
            }
            result[index] = result[index].absorbing(show)
        }

        items = result.sorted { $0.startsAt < $1.startsAt }
        return added
    }

    /// 标记某个数据源刷新成功。
    public mutating func markFetched(_ source: Show.Source, at date: Date = .now) {
        switch source {
        case .mujian: lastAPIFetchAt = date
        case .calendar: lastCalendarFetchAt = date
        }
    }

    /// 清掉散场超过保留期的场次。
    ///
    /// 缓存不清会无限增长，而过期演出既排不出提醒也开不了岛，留着只是噪声。
    public mutating func prune(now: Date = .now, retention: TimeInterval = 86_400) {
        items.removeAll { now > $0.islandDismissAt.addingTimeInterval(retention) }
    }
}

extension Show {

    /// 跨数据源的身份键。
    ///
    /// 幕间 API 给的是记录 id；它同步进系统日历的 CalDAV 事件 UID 是 `<recordID>@mujian`
    /// （见幕间 `internal/ics/ics.go`）。两边必须归一到同一个键。
    /// 用户在日历里自己建的、UID 不带 `@mujian` 的事件归到 `calendar:` 命名空间，
    /// 不会和幕间的记录误合并。
    public var identity: String {
        let suffix = "@mujian"
        if id.hasSuffix(suffix) {
            return "mujian:" + id.dropLast(suffix.count)
        }
        return "\(source.rawValue):\(id)"
    }

    /// 是否指向同一场演出。
    ///
    /// 两条判据取或：
    /// 1. `identity` 相同——幕间记录 id 与 CalDAV 的 `<id>@mujian` 归一后一致，这是硬匹配；
    /// 2. 同名且开演时间相差 15 分钟内——`EKEvent` 不暴露 ICS 的 UID，
    ///    靠 `eventIdentifier` 无法与幕间 id 对齐，只能退到模糊匹配兜底。
    ///    宁可误并（少一次提醒）也不要重复（两次提醒）。
    public func isSameShow(as other: Show) -> Bool {
        if identity == other.identity { return true }
        return name == other.name
            && abs(startsAt.timeIntervalSince(other.startsAt)) <= 900
    }

    /// 用另一条同源记录补全自己，返回合并结果。
    ///
    /// 冲突时以幕间 API 为准：它带座位与演出时长，日历事件只有标题和地点。
    /// 补字段采用「谁有谁填」，避免用 nil 覆盖掉对方已有的值。
    public func absorbing(_ other: Show) -> Show {
        // API 数据更全，作为合并基准；`self` 里独有的字段再补回去。
        let base = other.source == .mujian && source != .mujian ? other : self
        let fallback = base.id == other.id ? self : other

        return Show(
            id: base.id,
            name: base.name.isEmpty ? fallback.name : base.name,
            venue: base.venue ?? fallback.venue,
            seat: base.seat ?? fallback.seat,
            startsAt: base.startsAt,
            endsAt: base.endsAt ?? fallback.endsAt,
            url: base.url ?? fallback.url,
            source: base.source
        )
    }
}
