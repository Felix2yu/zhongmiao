import Foundation

/// 一条「写进系统」的提醒锚点。
///
/// 与本地通知的区别：系统日历与提醒事项由**系统**持有。App 被杀、描述文件过期、
/// 甚至重装（日历数据仍在系统里）都不影响它到点触发；本地通知则受单 App 64 条
/// 上限约束，且依赖 App 曾经排过它。
/// 免费账号没有 APNs，这是唯一能长期可靠、且不占本地通知预算的到点通道。
///
/// 幂等靠备注里的一行标记（`zm-anchor:<identifier>`）——`EKEvent` 没有可自由写入的
/// 自定义字段，而 `eventIdentifier` 由系统生成、跨设备不稳定，不能当业务键。
public struct SystemAnchor: Hashable, Sendable {

    public var serviceID: String
    /// 业务类型：`birthday` / `anniversary` / `care` / `diary` / `period` / `task` …
    public var kind: String
    /// 该业务对象自身的稳定键（原始 id 或日期串）。
    public var key: String
    public var title: String
    public var notes: String?
    public var fireDate: Date
    public var isAllDay: Bool
    /// 每年重复：生日、纪念日这类一次写入终身有效的项。
    public var repeatsYearly: Bool
    /// 回跳用的深链（`zhongmiao://`）。日历事件写进 `url`，提醒事项只能进备注。
    public var url: URL?

    public init(
        serviceID: String,
        kind: String,
        key: String,
        title: String,
        notes: String? = nil,
        fireDate: Date,
        isAllDay: Bool = false,
        repeatsYearly: Bool = false,
        url: URL? = nil
    ) {
        self.serviceID = serviceID
        self.kind = kind
        self.key = key
        self.title = title
        self.notes = notes
        self.fireDate = fireDate
        self.isAllDay = isAllDay
        self.repeatsYearly = repeatsYearly
        self.url = url
    }

    /// 写进系统时使用的稳定标识，跨同步轮次不变。
    public var identifier: String {
        "zm.\(serviceID).\(kind).\(IntegrationReminderID.sanitize(key))"
    }

    /// 带锚点标记的备注全文（写入系统时用这个，不要用 `notes`）。
    /// 日历有 `url` 字段；提醒事项没有，所以只有提醒通道把深链写进备注。
    public var markedNotes: String {
        SystemAnchorMarker.embed(
            identifier,
            in: notes,
            url: channel == .reminder ? url : nil
        )
    }
}

/// 锚点落到哪个系统通道。
public enum SystemChannel: String, Hashable, Sendable {
    /// 系统日历：支持全天与每年重复，适合生日、纪念日、观赏窗口。
    case calendar
    /// 提醒事项：有明确的到期时刻、且天然可勾选，适合养护、日记、任务。
    case reminder
}

extension SystemAnchor {

    /// 全天或每年重复的走日历；有明确时刻的走提醒事项。
    ///
    /// 提醒事项支持到期时间 + 勾选完成，但不适合表达「每年一次」与全天；
    /// 日历反过来。区分开是为了不把两类语义硬塞进同一个通道。
    public var channel: SystemChannel {
        (isAllDay || repeatsYearly) ? .calendar : .reminder
    }

    /// 从已排好的本地提醒转出一条系统锚点。
    ///
    /// 通知 id 形如 `integration.<service>.<kind>.<key>.<yyyyMMdd>`，
    /// 前四段正好是锚点需要的全部信息，所以各应用的 Planner 不需要再改一次。
    /// 解析不出来（不是这条约定生成的 id）就返回 nil，由调用方跳过。
    ///
    /// 生日/纪念日默认按年重复；农历日期无法用 EventKit 的年度规则表达，
    /// Planner 会显式传 `repeatsYearly = "0"`，让它们继续走一次性提醒。
    public init?(
        reminder: PlannedReminder,
        isAllDay: Bool = false,
        repeatsYearly: Bool = false
    ) {
        let parts = reminder.id.dropFirst(IntegrationReminderID.prefix.count).split(separator: ".")
        guard parts.count >= 4 else { return nil }
        let serviceID = String(parts[0])
        let kind = String(parts[1])
        self.serviceID = serviceID
        self.kind = kind
        self.key = String(parts[2])
        self.title = reminder.title
        self.notes = reminder.body
        self.fireDate = reminder.fireDate
        self.isAllDay = isAllDay
        let yearlyByKind = kind == "anniversary" || kind == "birthday"
        let yearlyFlag = reminder.userInfo["repeatsYearly"].map { $0 == "1" } ?? yearlyByKind
        self.repeatsYearly = repeatsYearly || yearlyFlag
        self.url = reminder.target.flatMap { DeepLink.url(serviceID: serviceID, target: $0) }
    }
}

/// 备注里的锚点标记。
public enum SystemAnchorMarker {

    public static let prefix = "zm-anchor:"

    public static func embed(_ identifier: String, in notes: String?, url: URL? = nil) -> String {
        var lines: [String] = []
        let base = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { lines.append(base) }
        if let url { lines.append(url.absoluteString) }
        lines.append("\(prefix)\(identifier)")
        return lines.joined(separator: "\n")
    }

    /// 从备注里取回锚点标识。系统可能改写备注（比如用户在日历里编辑过），
    /// 所以逐行找而不是按后缀截取。
    public static func extract(from notes: String?) -> String? {
        guard let notes else { return nil }
        for line in notes.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.hasPrefix(prefix) else { continue }
            let value = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}

/// 写入预算。系统日历不属于 App，写太多等于污染用户的日历，
/// 所以即便没有 64 条限制，也要自己设一个上限。
public enum SystemAnchorBudget {

    public static let perServiceLimit = 60
    public static let totalLimit = 200

    /// 过期项丢掉、按标识去重、按时间排序，再按每应用与总量截断。
    public static func apply(
        to anchors: [SystemAnchor],
        now: Date = .now
    ) -> [SystemAnchor] {
        var seen: Set<String> = []
        let sorted = anchors
            .filter { $0.fireDate > now }
            .sorted { lhs, rhs in
                if lhs.fireDate == rhs.fireDate { return lhs.identifier < rhs.identifier }
                return lhs.fireDate < rhs.fireDate
            }

        var perService: [String: Int] = [:]
        var result: [SystemAnchor] = []
        for anchor in sorted {
            guard !seen.contains(anchor.identifier) else { continue }
            let used = perService[anchor.serviceID, default: 0]
            guard used < perServiceLimit else { continue }
            guard result.count < totalLimit else { break }
            seen.insert(anchor.identifier)
            perService[anchor.serviceID] = used + 1
            result.append(anchor)
        }
        return result
    }
}
