import Testing
import Foundation
@testable import ZhongmiaoCore

@Suite("开演闹钟计划")
struct ShowAlarmTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func future(_ hours: Double) -> Date {
        now.addingTimeInterval(hours * 3600)
    }

    @Test("提前量归到最近档位")
    func clampedLead() {
        #expect(ShowAlarm.clampedLead(10) == 30)
        #expect(ShowAlarm.clampedLead(45) == 30 || ShowAlarm.clampedLead(45) == 60)
        #expect(ShowAlarm.clampedLead(60) == 60)
        #expect(ShowAlarm.clampedLead(999) == 120)
        #expect(ShowAlarm.leadOptions.contains(ShowAlarm.clampedLead(75)))
    }

    @Test("响铃时刻是开演减去提前量")
    func fireDate() {
        let starts = future(3)
        let fire = ShowAlarm.fireDate(startsAt: starts, leadMinutes: 30)
        #expect(abs(fire.timeIntervalSince(starts) + 1800) < 0.001)
    }

    @Test("响铃时刻已过或太近的场次不可排")
    func schedulability() {
        // 差 30 秒就响：来不及，也解释不清，不排。
        let tooSoon = now.addingTimeInterval(30)
        #expect(ShowAlarm.isSchedulable(fireDate: tooSoon, now: now) == false)
        #expect(ShowAlarm.isSchedulable(fireDate: now.addingTimeInterval(-10), now: now) == false)
        #expect(ShowAlarm.isSchedulable(fireDate: now.addingTimeInterval(600), now: now) == true)
    }

    @Test("不可排时计划为 nil")
    func planNilWhenPast() {
        let plan = ShowAlarm.plan(
            for: "42",
            name: "雷雨",
            startsAt: now.addingTimeInterval(60),
            leadMinutes: 30,
            now: now
        )
        #expect(plan == nil)
    }

    @Test("可排时给出完整计划")
    func planBuilt() {
        let starts = future(5)
        let plan = ShowAlarm.plan(
            for: "42",
            name: "雷雨",
            venue: "首都剧场",
            startsAt: starts,
            leadMinutes: 60,
            now: now
        )
        #expect(plan?.showID == "42")
        #expect(plan?.fireDate == starts.addingTimeInterval(-3600))
    }

    @Test("计划的提前量归一到档位")
    func planLeadClamped() {
        let plan = ShowAlarm.plan(
            for: "7",
            name: "茶馆",
            startsAt: future(6),
            leadMinutes: 75,
            now: now
        )
        #expect(plan?.leadMinutes == ShowAlarm.clampedLead(75))
        #expect(ShowAlarm.leadOptions.contains(plan?.leadMinutes ?? 0))
        // 响铃时刻与归一后的提前量必须一致，否则界面显示的时刻会和系统对不上。
        #expect(plan?.fireDate == plan?.startsAt.addingTimeInterval(-TimeInterval(plan!.leadMinutes) * 60))
    }

    @Test("同一场演出始终得到同一个闹钟 id")
    func identifierStable() {
        let first = ShowAlarm.identifier(forShowID: "1024")
        let second = ShowAlarm.identifier(forShowID: "1024")
        #expect(first == second)
        #expect(ShowAlarm.identifier(forShowID: "1025") != first)
        // 版本号与变体位：第 7 字节高 4 位应为 0100（v4 形状）。
        #expect(first.uuid.6 >> 4 == 0x4)
    }

    @Test("超上限时保留最近的几场")
    func trimKeepsNearest() {
        let plans = (1...8).map { index in
            ShowAlarmPlan(
                showID: "s\(index)",
                name: "剧目\(index)",
                startsAt: future(Double(index) * 10),
                fireDate: future(Double(index) * 10 - 1),
                leadMinutes: 60
            )
        }
        let result = ShowAlarm.trim(plans)
        #expect(result.kept.count == ShowAlarm.maxConcurrent)
        #expect(result.dropped.count == 3)
        #expect(result.kept.map(\.showID) == ["s1", "s2", "s3", "s4", "s5"])
        // 未超限时一个都不丢。
        #expect(ShowAlarm.trim(Array(plans.prefix(2))).dropped.isEmpty)
    }
}
