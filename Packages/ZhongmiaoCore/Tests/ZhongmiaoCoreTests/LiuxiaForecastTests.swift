import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("流霞预报")
struct LiuxiaForecastTests {

    private let zone = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: string)!
    }

    private func event(
        _ city: String = "西安",
        _ day: String,
        _ time: String?,
        _ kind: LiuxiaEvent.Kind,
        _ quality: Double?,
        model: String? = nil
    ) -> LiuxiaEvent {
        LiuxiaEvent(city: city, date: day, time: time, kind: kind, quality: quality, model: model)
    }

    @Test("质量文案与网页版一致")
    func qualityLabels() {
        #expect(LiuxiaQualityScale.label(nil) == "—")
        #expect(LiuxiaQualityScale.label(0.01) == "微微烧")
        #expect(LiuxiaQualityScale.label(0.3) == "小烧到中等烧")
        #expect(LiuxiaQualityScale.label(0.5) == "中等烧")
        #expect(LiuxiaQualityScale.label(0.7) == "中等到大烧")
        #expect(LiuxiaQualityScale.label(0.9) == "不完美大烧")
        #expect(LiuxiaQualityScale.label(1.2) == "典型大烧")
        #expect(LiuxiaQualityScale.label(1.8) == "优质大烧")
        #expect(LiuxiaQualityScale.label(2.2) == "世纪大烧")
        #expect(LiuxiaQualityScale.label(3.0) == "超级大烧")
    }

    @Test("优质界线是优质大烧（≥1.5）")
    func premiumThreshold() {
        #expect(!LiuxiaQualityScale.isPremium(1.49))
        #expect(LiuxiaQualityScale.isPremium(1.5))
        #expect(!LiuxiaQualityScale.isPremium(nil))
        #expect(LiuxiaQualityScale.tier(1.6) == 4)
        #expect(LiuxiaQualityScale.tier(0.9) == 3)
        #expect(LiuxiaQualityScale.tier(0.5) == 2)
        #expect(LiuxiaQualityScale.tier(0.1) == 1)
        #expect(LiuxiaQualityScale.tier(nil) == 0)
    }

    @Test("同一天同类型多模型时取质量最高的一条")
    func bestPerSlot() {
        let events = [
            event("西安", "2026-10-27", "18:10", .evening, 0.6, model: "a"),
            event("西安", "2026-10-27", "18:10", .evening, 1.7, model: "b"),
            event("西安", "2026-10-27", "18:10", .evening, 1.2, model: "c"),
            event("西安", "2026-10-27", "06:40", .morning, 0.3, model: "a"),
            event("成都", "2026-10-27", "18:20", .evening, 2.1, model: "a")
        ]
        let best = LiuxiaForecast.bestPerSlot(events)
        #expect(best.count == 3)
        let evening = best.first { $0.city == "西安" && $0.kind == .evening }
        #expect(evening?.quality == 1.7)
        #expect(evening?.model == "b")
        #expect(best.contains { $0.city == "成都" && $0.quality == 2.1 })
    }

    @Test("只保留未来 48 小时内、按时间升序")
    func upcoming() {
        let now = date("2026-10-27 15:00")
        let events = [
            event("西安", "2026-10-27", "06:40", .morning, 0.9),   // 已过
            event("西安", "2026-10-27", "18:12", .evening, 1.8),   // 3 小时后
            event("西安", "2026-10-28", "06:35", .morning, 1.6),   // 明天早上
            event("西安", "2026-10-30", "06:35", .morning, 2.0)    // 超出 48 小时
        ]
        let result = LiuxiaForecast.upcoming(events, now: now, timeZone: zone)
        #expect(result.count == 2)
        #expect(result.first?.time == "18:12")
        #expect(result.last?.time == "06:35")
    }

    @Test("缺时刻的场次不参与排序")
    func upcomingWithoutTime() {
        let now = date("2026-10-27 15:00")
        let events = [event("西安", "2026-10-27", nil, .evening, 1.9)]
        #expect(LiuxiaForecast.upcoming(events, now: now, timeZone: zone).isEmpty)
    }

    @Test("优质场次按质量降序，缺质量的剔除")
    func premium() {
        let events = [
            event("西安", "2026-10-28", "06:35", .morning, 1.6),
            event("西安", "2026-10-27", "18:12", .evening, 2.3),
            event("西安", "2026-10-29", "06:40", .morning, 0.9),
            event("西安", "2026-10-29", "18:20", .evening, nil)
        ]
        let result = LiuxiaForecast.premium(in: events)
        #expect(result.map(\.quality) == [2.3, 1.6])
    }

    @Test("倒计时文案")
    func countdown() {
        let now = date("2026-10-27 15:00")
        #expect(LiuxiaForecast.countdown(from: now, to: date("2026-10-27 18:49")) == "3 小时 49 分")
        #expect(LiuxiaForecast.countdown(from: now, to: date("2026-10-27 15:12")) == "12 分钟")
        #expect(LiuxiaForecast.countdown(from: now, to: date("2026-10-27 17:00")) == "2 小时")
        #expect(LiuxiaForecast.countdown(from: now, to: date("2026-10-28 18:00")) == "1 天 3 小时")
        #expect(LiuxiaForecast.countdown(from: now, to: date("2026-10-27 14:00")) == "已过")
    }
}
