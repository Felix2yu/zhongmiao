import Foundation

/// 一场演出的「开演闹钟」计划。
///
/// 与本地通知的分工写在前面，免得后面做混：
/// - 本地通知是**默认就有**的：提前 4 小时投一条，不打扰，专注模式下会被静默；
/// - 闹钟是**逐场显式开启**的加强通道：由系统持有、覆盖静音与专注模式，
///   代价是到点一定会响。所以它只能是用户自己按下的开关，不能替他决定。
public struct ShowAlarmPlan: Codable, Equatable, Sendable, Identifiable {

    public var showID: String
    public var name: String
    public var venue: String?
    public var seat: String?
    /// 开演时刻。
    public var startsAt: Date
    /// 闹钟响铃时刻（开演前 `leadMinutes` 分钟）。
    public var fireDate: Date
    /// 这一场自己的提前量（分钟），已归一到 `ShowAlarm.leadOptions` 档位。
    public var leadMinutes: Int

    public var id: String { showID }

    public init(
        showID: String,
        name: String,
        venue: String? = nil,
        seat: String? = nil,
        startsAt: Date,
        fireDate: Date,
        leadMinutes: Int
    ) {
        self.showID = showID
        self.name = name
        self.venue = venue
        self.seat = seat
        self.startsAt = startsAt
        self.fireDate = fireDate
        self.leadMinutes = leadMinutes
    }
}

/// 闹钟的纯逻辑：标识符、时刻、上限。
///
/// 全部是不依赖 AlarmKit 的纯函数，所以 `swift test` 能直接覆盖——
/// AlarmKit 只存在于 iOS 26+，模拟器与 macOS 都跑不了，能测的部分必须挪到这里。
public enum ShowAlarm {

    /// 同时持有的闹钟上限。
    ///
    /// 系统自身也有上限（超出会抛 `maximumLimitReached`），但那是"响不过来"的兜底；
    /// 这里限得更紧，是因为闹钟会穿透专注模式——同一天响五次的体验是灾难。
    public static let maxConcurrent = 5

    /// 可选的提前量（分钟）。给固定档位而不是自由输入，
    /// 免得出现「提前 7 分钟」这种既没用又难解释的值。
    public static let leadOptions = [30, 60, 90, 120]

    public static let defaultLeadMinutes = 60

    /// 铃声响起至少要留出的余量：排完立刻响的闹钟只会让人莫名其妙。
    public static let minimumLead: TimeInterval = 60

    /// 把任意分钟数归到最近的档位。
    public static func clampedLead(_ minutes: Int) -> Int {
        guard let first = leadOptions.first, let last = leadOptions.last else { return defaultLeadMinutes }
        if minutes <= first { return first }
        if minutes >= last { return last }
        return leadOptions.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? defaultLeadMinutes
    }

    public static func fireDate(startsAt: Date, leadMinutes: Int) -> Date {
        startsAt.addingTimeInterval(-TimeInterval(clampedLead(leadMinutes)) * 60)
    }

    /// 这场还能不能排。已过响铃时刻的场次排上去毫无意义。
    public static func isSchedulable(fireDate: Date, now: Date = .now) -> Bool {
        fireDate.timeIntervalSince(now) >= minimumLead
    }

    /// 由演出计划构造闹钟计划；不可排时返回 nil。
    public static func plan(
        for showID: String,
        name: String,
        venue: String? = nil,
        seat: String? = nil,
        startsAt: Date,
        leadMinutes: Int,
        now: Date = .now
    ) -> ShowAlarmPlan? {
        let lead = clampedLead(leadMinutes)
        let fire = startsAt.addingTimeInterval(-TimeInterval(lead) * 60)
        guard isSchedulable(fireDate: fire, now: now) else { return nil }
        return ShowAlarmPlan(
            showID: showID,
            name: name,
            venue: venue,
            seat: seat,
            startsAt: startsAt,
            fireDate: fire,
            leadMinutes: lead
        )
    }

    /// 超出上限时该留哪些：保留**最近**的几场，远的让位。
    ///
    /// 理由：远的场次还有机会再开一次，眼前这场错过就没有了。
    public static func trim(
        _ plans: [ShowAlarmPlan],
        limit: Int = maxConcurrent
    ) -> (kept: [ShowAlarmPlan], dropped: [ShowAlarmPlan]) {
        guard plans.count > limit else { return (plans, []) }
        let sorted = plans.sorted { $0.fireDate < $1.fireDate }
        return (Array(sorted.prefix(limit)), Array(sorted.dropFirst(limit)))
    }

    // MARK: - 稳定标识符

    /// 由演出 id 派生出稳定的闹钟 `UUID`。
    ///
    /// AlarmKit 只认 `UUID`，而 `UUID()` 每次都不同——重复排会堆出多个闹钟。
    /// 这里用 FNV-1a 的两轮不同种子拼出 128 位，保证：
    /// - 同一场演出每次算出同一个 id（重排=覆盖，不会堆积）；
    /// - 跨进程、跨重启一致（`String.hashValue` 不行，会随进程变）。
    /// 代价是不可逆：想从系统返回的 `Alarm.id` 反查演出，得靠本地记录。
    public static func identifier(forShowID showID: String) -> UUID {
        let bytes = Array(showID.utf8)
        let high = fnv1a64(bytes, seed: 0x9E37_79B9_7F4A_7C15)
        let low = fnv1a64(bytes, seed: 0xCBF2_9CE4_8422_2325)

        var raw: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &raw) { buffer in
            buffer.storeBytes(of: high.bigEndian, toByteOffset: 0, as: UInt64.self)
            buffer.storeBytes(of: low.bigEndian, toByteOffset: 8, as: UInt64.self)
        }
        // 按 RFC 4122 标上版本号与变体位：不标也能用，但标了不会被系统当成畸形值。
        raw.6 = (raw.6 & 0x0F) | 0x40
        raw.8 = (raw.8 & 0x3F) | 0x80
        return UUID(uuid: raw)
    }

    /// FNV-1a 64 位。种子即初始偏移，换种子就得到一条独立的散列。
    private static func fnv1a64(_ bytes: [UInt8], seed: UInt64) -> UInt64 {
        let prime: UInt64 = 0x0100_0000_01B3
        var hash = seed
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
