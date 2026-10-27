import Foundation

/// 一次朝霞 / 晚霞预报。
///
/// 只放纯数据与纯计算，界面和网络在 App 里——这样「哪一场即将到来」「同一天多模型取哪个」
/// 都能直接用 `swift test` 覆盖，不必起模拟器。
public struct LiuxiaEvent: Hashable, Sendable, Identifiable {

    public enum Kind: String, Sendable, CaseIterable {
        case morning
        case evening

        public var title: String {
            switch self {
            case .morning: "朝霞"
            case .evening: "晚霞"
            }
        }

        public var symbol: String {
            switch self {
            case .morning: "sunrise"
            case .evening: "sunset"
            }
        }

        /// 观赏窗口提示（网页版的说法：日出前 20–30 分钟、日落后 15–30 分钟）。
        public var viewingHint: String {
            switch self {
            case .morning: "日出前 20–30 分钟到位"
            case .evening: "日落后 15–30 分钟到位"
            }
        }
    }

    public var city: String
    /// `yyyy-MM-dd`，服务端按本地日期给。
    public var date: String
    /// `HH:mm`，可能缺失。
    public var time: String?
    public var kind: Kind
    public var quality: Double?
    public var aod: Double?
    public var model: String?

    public var id: String { "\(date)|\(kind.rawValue)|\(time ?? "-")|\(city)|\(model ?? "-")" }

    public init(
        city: String,
        date: String,
        time: String?,
        kind: Kind,
        quality: Double? = nil,
        aod: Double? = nil,
        model: String? = nil
    ) {
        self.city = city
        self.date = date
        self.time = time
        self.kind = kind
        self.quality = quality
        self.aod = aod
        self.model = model
    }

    /// 发生时刻。缺日期或缺时刻时返回 nil（不猜）。
    public func occursAt(timeZone: TimeZone = .current) -> Date? {
        guard let time, !time.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let normalized = time.count >= 5 ? String(time.prefix(5)) : time
        return formatter.date(from: "\(date) \(normalized)")
    }

    public var qualityLabel: String { LiuxiaQualityScale.label(quality) }

    public var isPremium: Bool { LiuxiaQualityScale.isPremium(quality) }
}

/// 质量分档。文案与流霞网页版保持一致，避免同一个数在两处叫不同名字。
public enum LiuxiaQualityScale {

    /// 网页版 `qualityLabel()` 的阈值：0.05 / 0.2 / 0.4 / 0.6 / 0.8 / 1.0 / 1.5 / 2.0 / 2.5。
    public static func label(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch value {
        case ..<0.05: return "微微烧"
        case ..<0.2: return "小烧"
        case ..<0.4: return "小烧到中等烧"
        case ..<0.6: return "中等烧"
        case ..<0.8: return "中等到大烧"
        case ..<1.0: return "不完美大烧"
        case ..<1.5: return "典型大烧"
        case ..<2.0: return "优质大烧"
        case ..<2.5: return "世纪大烧"
        default: return "超级大烧"
        }
    }

    /// 0 无数据 / 1 弱 / 2 一般 / 3 值得看 / 4 优质。只为配色与强调服务。
    public static func tier(_ value: Double?) -> Int {
        guard let value else { return 0 }
        switch value {
        case ..<0.4: return 1
        case ..<0.8: return 2
        case ..<1.5: return 3
        default: return 4
        }
    }

    /// 「优质」的界线：优质大烧及以上（≥ 1.5）。
    public static func isPremium(_ value: Double?) -> Bool {
        (value ?? 0) >= 1.5
    }
}

public enum LiuxiaForecast {

    /// 同一天、同一类型、同一城市会有多个模型的结果：取质量最高的一条。
    /// 质量相同时保留先出现的（服务端顺序即抓取顺序，稳定即可）。
    public static func bestPerSlot(_ events: [LiuxiaEvent]) -> [LiuxiaEvent] {
        var best: [String: LiuxiaEvent] = [:]
        var order: [String] = []
        for event in events {
            let key = "\(event.city)|\(event.date)|\(event.kind.rawValue)"
            if let existing = best[key] {
                if (event.quality ?? -.infinity) > (existing.quality ?? -.infinity) {
                    best[key] = event
                }
            } else {
                best[key] = event
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    /// 尚未开始的场次，按时间升序。缺时刻的场次无法判断先后，直接丢掉。
    public static func upcoming(
        _ events: [LiuxiaEvent],
        now: Date = .now,
        horizonHours: Double = 48,
        timeZone: TimeZone = .current
    ) -> [LiuxiaEvent] {
        let limit = now.addingTimeInterval(horizonHours * 3600)
        return events
            .compactMap { event -> (LiuxiaEvent, Date)? in
                guard let at = event.occursAt(timeZone: timeZone), at > now, at <= limit else { return nil }
                return (event, at)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// 即将到来的优质场次：先按质量筛，再按时间排。质量缺失的不要。
    public static func premium(
        in events: [LiuxiaEvent],
        minimumQuality: Double = 1.5
    ) -> [LiuxiaEvent] {
        events
            .filter { ($0.quality ?? -.infinity) >= minimumQuality }
            .sorted { ($0.quality ?? 0) > ($1.quality ?? 0) }
    }

    /// 倒计时文案：`3 小时 49 分`、`12 分钟`、`已过`。
    public static func countdown(from now: Date, to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "已过" }
        let minutes = Int((seconds / 60).rounded(.down))
        if minutes < 60 { return "\(max(minutes, 1)) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours < 24 {
            return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
        }
        let days = hours / 24
        return "\(days) 天 \(hours % 24) 小时"
    }
}
