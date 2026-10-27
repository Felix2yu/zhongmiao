import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("原生提醒计划")
struct IntegrationReminderTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func reminder(
        _ service: String,
        key: String,
        offset: TimeInterval,
        now: Date
    ) -> PlannedReminder {
        PlannedReminder(
            id: IntegrationReminderID.make(
                serviceID: service,
                kind: "test",
                key: key,
                date: now.addingTimeInterval(offset)
            ),
            serviceID: service,
            title: key,
            body: "",
            fireDate: now.addingTimeInterval(offset)
        )
    }

    @Test("ID 带服务、类型、日期，且可反解服务")
    func identifierShape() {
        let id = IntegrationReminderID.make(
            serviceID: "bili-history",
            kind: "birthday",
            key: "person.42",
            date: base,
            timeZone: TimeZone(identifier: "Asia/Shanghai")!
        )
        #expect(id.hasPrefix("integration.bili-history.birthday."))
        #expect(!id.contains("person.42"))
        #expect(IntegrationReminderID.serviceID(from: id) == "bili-history")
        #expect(IntegrationReminderID.isIntegrationID(id))
        #expect(!IntegrationReminderID.isIntegrationID("show.abc"))
    }

    @Test("过期项被丢弃并按时间排序")
    func dropsPastAndSorts() {
        let now = base
        let plans = [
            reminder("qingye", key: "late", offset: 3_600, now: now),
            reminder("qingye", key: "past", offset: -60, now: now),
            reminder("qingye", key: "soon", offset: 60, now: now)
        ]
        let result = IntegrationReminderBudget.apply(to: plans, now: now)
        #expect(result.map(\.title) == ["soon", "late"])
    }

    @Test("同一应用最多 12 条")
    func perServiceLimit() {
        let now = base
        let plans = (0..<20).map { index in
            reminder("qingye", key: "task-\(index)", offset: TimeInterval(60 * (index + 1)), now: now)
        }
        let result = IntegrationReminderBudget.apply(to: plans, now: now)
        #expect(result.count == IntegrationReminderBudget.perServiceLimit)
        #expect(result.first?.title == "task-0")
    }

    @Test("总量最多 48 条")
    func totalLimit() {
        let now = base
        var plans: [PlannedReminder] = []
        for service in ["a", "b", "c", "d", "e"] {
            for index in 0..<12 {
                plans.append(
                    reminder(service, key: "k-\(index)", offset: TimeInterval(60 * (index + 1)), now: now)
                )
            }
        }
        let result = IntegrationReminderBudget.apply(to: plans, now: now)
        #expect(result.count == IntegrationReminderBudget.totalLimit)
    }

    @Test("重复 ID 只保留一条")
    func dedupe() {
        let now = base
        let same = reminder("qingye", key: "same", offset: 60, now: now)
        let result = IntegrationReminderBudget.apply(to: [same, same], now: now)
        #expect(result.count == 1)
    }
}
