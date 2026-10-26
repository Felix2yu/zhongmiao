import Foundation

/// 一场演出。来源可以是幕间 API，也可以是系统日历（幕间 CalDAV 同步过去的事件）。
///
/// 之所以要独立于数据源：提醒排程、灵动岛、通知三处都只认这一个形态，
/// 换数据源或加第三个来源时不必改下游。
public struct Show: Codable, Identifiable, Hashable, Sendable {

    public enum Source: String, Codable, Sendable, CaseIterable {
        /// 幕间 `GET /api/records/upcoming`。
        case mujian
        /// 系统日历（幕间 CalDAV 同步的事件）。
        case calendar
    }

    /// 稳定 id：幕间记录 id，或日历事件的指纹。
    ///
    /// 它同时是本地通知的请求标识符和灵动岛的幂等键，
    /// 所以必须跨进程、跨重启稳定——不能用 `String.hashValue`。
    public var id: String
    public var name: String
    /// 场馆。优先场馆地址，没有就退到城市。
    public var venue: String?
    public var seat: String?
    /// 开演时间。
    public var startsAt: Date
    /// 预计散场时间。幕间 `duration` 为 0（未知）时为 nil。
    public var endsAt: Date?
    /// 点击通知或灵动岛要打开的页面。
    public var url: URL?
    public var source: Source

    public init(
        id: String,
        name: String,
        venue: String? = nil,
        seat: String? = nil,
        startsAt: Date,
        endsAt: Date? = nil,
        url: URL? = nil,
        source: Source
    ) {
        self.id = id
        self.name = name
        self.venue = venue
        self.seat = seat
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.url = url
        self.source = source
    }
}

/// 演出当前所处的阶段。灵动岛用它切换「距开演 / 演出中 / 已结束」三态。
public enum ShowPhase: String, Codable, Sendable, Hashable, CaseIterable {
    /// 尚未开演。
    case scheduled
    /// 演出进行中。
    case ongoing
    /// 已结束。
    case ended
}

/// 提醒与灵动岛的时间口径。
///
/// 两个提前量是**两件事**，不要合并成一个设置：
/// - 通知提前量（默认 4 小时）决定「提前多久弹提醒」，是用户的主观偏好；
/// - 灵动岛提前量（默认贴着系统上限 8 小时）决定「最早什么时候允许开岛」。
///   岛的触发点是快捷指令的固定时刻（10:00 / 15:00）或用户打开 App，
///   时刻不由我们决定，所以窗口开得越大，被自动化命中的概率越高。
public enum ShowReminder {

    /// 灵动岛活跃时长上限，系统硬限制：8 小时后系统立即从岛移除。
    public static let islandMaxLead: TimeInterval = 8 * 3600
    /// 灵动岛提前量默认值：贴着上限，能开就开。
    public static let defaultIslandLead: TimeInterval = islandMaxLead
    /// 本地通知提前量默认值。
    ///
    /// 4 小时是照着观演习惯定的：午场 13:00–14:00 开演 → 09:00–10:00 提醒，
    /// 夜场 19:00–19:30 开演 → 15:00–15:30 提醒，都落在起床后与下班前。
    public static let defaultReminderLead: TimeInterval = 4 * 3600
    /// 幕间 `duration` 未知时用于判断「是否已结束」的兜底演出时长。
    public static let fallbackDuration: TimeInterval = 3 * 3600
    /// 散场后多久收起灵动岛。
    public static let islandDismissDelay: TimeInterval = 30 * 60

    /// 把提前量夹到合法区间：不能为负，也不能超过系统上限。
    public static func clampedIslandLead(_ lead: TimeInterval) -> TimeInterval {
        min(max(lead, 0), islandMaxLead)
    }
}

extension Show {

    /// 当前阶段。
    ///
    /// `endsAt` 缺失（幕间没填时长）时用兜底时长判断，避免一场演出永远停在「演出中」。
    public func phase(now: Date = .now) -> ShowPhase {
        if now < startsAt { return .scheduled }
        let end = endsAt ?? startsAt.addingTimeInterval(ShowReminder.fallbackDuration)
        return now < end ? .ongoing : .ended
    }

    /// 收起灵动岛的时刻：散场后 30 分钟。
    public var islandDismissAt: Date {
        let end = endsAt ?? startsAt.addingTimeInterval(ShowReminder.fallbackDuration)
        return end.addingTimeInterval(ShowReminder.islandDismissDelay)
    }

    /// 是否该把灵动岛亮起来：`now` 落在「开演前 lead」到「散场」之间。
    ///
    /// 已结束的场次不开——否则打开 App 时会给三小时前散场的演出补一个岛。
    public func shouldStartIsland(
        now: Date = .now,
        lead: TimeInterval = ShowReminder.defaultIslandLead
    ) -> Bool {
        let earliest = startsAt.addingTimeInterval(-ShowReminder.clampedIslandLead(lead))
        guard now >= earliest else { return false }
        return phase(now: now) != .ended
    }

    /// 本地提醒的触发时刻。已经过了就返回 nil（不排过期提醒）。
    public func reminderDate(
        lead: TimeInterval = ShowReminder.defaultReminderLead,
        now: Date = .now
    ) -> Date? {
        let date = startsAt.addingTimeInterval(-max(0, lead))
        return date > now ? date : nil
    }
}

// MARK: - 幕间 API

/// 幕间 `GET /api/records/upcoming` 的返回体。
public struct MujianUpcomingResponse: Decodable, Sendable {
    public var items: [MujianUpcomingRecord]
    public var days: Int?

    private enum CodingKeys: String, CodingKey {
        case items, days
    }

    /// 逐字段解码：`items` 缺失时退化为空数组，而不是让整份响应失败。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([MujianUpcomingRecord].self, forKey: .items) ?? []
        days = try container.decodeIfPresent(Int.self, forKey: .days)
    }
}

/// 幕间未来演出的条目。
///
/// 字段全部可选：接口加字段、或某条记录缺字段，都不能让整份缓存解码失败——
/// 缓存解码失败等于清空用户所有已排好的提醒。
public struct MujianUpcomingRecord: Decodable, Sendable {
    public var id: String?
    public var name: String?
    /// 开演时间，unix 秒。
    public var date: Int64?
    /// 演出时长（分钟），0 或缺失表示未知。
    public var duration: Int?
    public var address: String?
    public var city: String?
    public var seat: String?
    public var categoryName: String?
    public var artistNames: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, name, date, duration, address, city, seat, categoryName
        case artistNames = "artist_names"
    }

    /// 转成标准演出形态。
    ///
    /// 缺 id、剧名、开演时间三者之一就放弃：没有开演时间的演出排不出提醒，
    /// 没有 id 的演出做不了通知去重，不如不进缓存。
    public func makeShow(baseURL: URL? = nil) -> Show? {
        guard let id, !id.isEmpty, let name, !name.isEmpty, let date else { return nil }
        let startsAt = Date(timeIntervalSince1970: TimeInterval(date))
        let endsAt: Date? = {
            guard let duration, duration > 0 else { return nil }
            return startsAt.addingTimeInterval(TimeInterval(duration) * 60)
        }()
        var show = Show(
            id: id,
            name: name,
            venue: address ?? city,
            seat: seat,
            startsAt: startsAt,
            endsAt: endsAt,
            source: .mujian
        )
        // 详情页路由是 /records/{id}（见幕间 web/src/routes/records/[id]）。
        if let baseURL {
            show.url = baseURL.appending(path: "records").appending(path: id)
        }
        return show
    }
}

// MARK: - 灵动岛

// `canImport(ActivityKit)` 在 macOS SDK 上同样为真（模块存在，但
// `ActivityAttributes` 被显式标记为 unavailable），所以必须再卡一道 os(iOS)：
// 否则 `swift test` 与 ZhongmiaoMac 会编译失败。
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// 灵动岛的静态数据：一场演出建岛之后不再变化的部分。
///
/// 放在 ZhongmiaoCore 是为了让主 App 与 Widget Extension 共用同一份定义
/// （ActivityKit 要求两侧的类型完全一致）。受 os(iOS) 保护，
/// macOS target 与 `swift test` 不受影响——ZhongmiaoCore 依旧只依赖 Foundation。
///
/// 注意 4KB 预算：只放岛内能渲染的字段，封面图一律不进。
@available(iOS 16.2, *)
public struct ShowActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable, Sendable {
        /// 演出阶段。岛上据此切换「距开演 / 演出中 / 已结束」。
        public var phase: ShowPhase
        /// 预计散场时间，未知时为 nil（岛内不显示散场时间）。
        public var endsAt: Date?

        public init(phase: ShowPhase, endsAt: Date? = nil) {
            self.phase = phase
            self.endsAt = endsAt
        }
    }

    /// 与 `Show.id` 相同，用作开岛的幂等键。
    public var showID: String
    public var name: String
    public var venue: String?
    public var seat: String?
    public var startsAt: Date
    /// 深链，字符串形态便于直接塞进 ActivityKit 载荷。
    public var url: String?

    public init(
        showID: String,
        name: String,
        venue: String? = nil,
        seat: String? = nil,
        startsAt: Date,
        url: String? = nil
    ) {
        self.showID = showID
        self.name = name
        self.venue = venue
        self.seat = seat
        self.startsAt = startsAt
        self.url = url
    }
}
#endif
