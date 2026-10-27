import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("青野养护提醒")
struct QingyeReminderPlannerTests {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ value: String) -> Date {
        QiansiLocalDate.parse(value, timeZone: shanghai)!
    }

    @Test("同一天的任务合并成一条摘要")
    func groupsByDay() {
        let now = date("2026-10-27T07:00:00")
        let plans = QingyeReminderPlanner.plan(
            tasks: [
                CareReminderInput(id: 1, plantName: "龟背竹", title: "浇水", nextDue: date("2026-10-27T00:00:00"), active: true),
                CareReminderInput(id: 2, plantName: "琴叶榕", title: "施肥", nextDue: date("2026-10-27T00:00:00"), active: true)
            ],
            hour: 8,
            minute: 0,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.count == 1)
        #expect(plans[0].title == "今日养护")
        #expect(plans[0].body.contains("龟背竹浇水"))
        #expect(plans[0].body.contains("琴叶榕施肥"))
    }

    @Test("过期任务归到今天，已过提醒时刻则不再排")
    func overdueClampedToToday() {
        let now = date("2026-10-27T07:00:00")
        let plans = QingyeReminderPlanner.plan(
            tasks: [
                CareReminderInput(id: 1, plantName: "龟背竹", title: "浇水", nextDue: date("2026-10-25T00:00:00"), active: true)
            ],
            hour: 8,
            minute: 0,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.count == 1)

        let late = QingyeReminderPlanner.plan(
            tasks: [
                CareReminderInput(id: 1, plantName: "龟背竹", title: "浇水", nextDue: date("2026-10-25T00:00:00"), active: true)
            ],
            hour: 6,
            minute: 0,
            now: now,
            timeZone: shanghai
        )
        #expect(late.isEmpty)
    }

    @Test("停用任务不排提醒")
    func inactiveSkipped() {
        let now = date("2026-10-27T07:00:00")
        let plans = QingyeReminderPlanner.plan(
            tasks: [
                CareReminderInput(id: 1, plantName: "龟背竹", title: "浇水", nextDue: date("2026-10-28T00:00:00"), active: false)
            ],
            hour: 8,
            minute: 0,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.isEmpty)
    }
}

@Suite("牵丝提醒")
struct QiansiReminderPlannerTests {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ value: String) -> Date {
        QiansiLocalDate.parse(value, timeZone: shanghai)!
    }

    @Test("生日按 remind_days 逐档排，今天一条")
    func anniversaryOffsets() {
        let now = date("2026-10-27T08:00:00")
        let plans = QiansiReminderPlanner.plan(
            anniversaries: [
                AnniversaryReminderInput(
                    id: "a1",
                    title: "妈妈生日",
                    personName: "妈妈",
                    nextDate: date("2026-11-03"),
                    daysUntil: 7,
                    remindDays: [7, 3, 1, 0]
                )
            ],
            events: [],
            customReminders: [],
            hour: 9,
            minute: 0,
            eventLeadDays: 1,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.count == 4)
        #expect(plans.first?.title == "妈妈 · 妈妈生日")
        #expect(plans.last?.body == "就是今天")
        #expect(plans.first?.fireDate == date("2026-10-27T09:00:00"))
    }

    @Test("已经过去的档位不再排")
    func pastOffsetsSkipped() {
        let now = date("2026-11-01T08:00:00")
        let plans = QiansiReminderPlanner.plan(
            anniversaries: [
                AnniversaryReminderInput(
                    id: "a1",
                    title: "生日",
                    nextDate: date("2026-11-03"),
                    daysUntil: 2,
                    remindDays: [7, 3, 1, 0]
                )
            ],
            events: [],
            customReminders: [],
            hour: 9,
            minute: 0,
            eventLeadDays: 1,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.count == 2)
    }

    @Test("约会按提前天数排，自定义提醒按 due_at")
    func eventsAndCustom() {
        let now = date("2026-10-27T08:00:00")
        let plans = QiansiReminderPlanner.plan(
            anniversaries: [],
            events: [
                EventReminderInput(
                    id: "e1",
                    title: "喝茶",
                    date: date("2026-10-29"),
                    people: ["老王"]
                )
            ],
            customReminders: [
                CustomReminderInput(
                    id: "r1",
                    title: "打电话",
                    dueAt: date("2026-10-28T15:00:00"),
                    personName: "妈妈"
                )
            ],
            hour: 9,
            minute: 0,
            eventLeadDays: 1,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.count == 2)
        #expect(plans.contains { $0.title == "约会 · 喝茶" && $0.fireDate == date("2026-10-28T09:00:00") })
        #expect(plans.contains { $0.title == "打电话" && $0.fireDate == date("2026-10-28T15:00:00") })
    }

    @Test("date-only 的自定义提醒用全局时刻")
    func midnightUsesGlobalClock() {
        let now = date("2026-10-27T08:00:00")
        let plans = QiansiReminderPlanner.plan(
            anniversaries: [],
            events: [],
            customReminders: [
                CustomReminderInput(
                    id: "r1",
                    title: "打电话",
                    dueAt: date("2026-10-28"),
                    personName: "妈妈"
                )
            ],
            hour: 9,
            minute: 30,
            eventLeadDays: 1,
            now: now,
            timeZone: shanghai
        )
        #expect(plans.first?.fireDate == date("2026-10-28T09:30:00"))
    }
}
