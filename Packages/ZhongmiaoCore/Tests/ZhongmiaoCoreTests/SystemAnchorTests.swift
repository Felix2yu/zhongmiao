import Foundation
import Testing
import ZhongmiaoCore

@Suite("系统锚点")
struct SystemAnchorTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func anchor(
        serviceID: String = "qiansi",
        kind: String = "anniversary",
        key: String = "17",
        fireDate: Date = Date(timeIntervalSince1970: 1_700_100_000)
    ) -> SystemAnchor {
        SystemAnchor(
            serviceID: serviceID,
            kind: kind,
            key: key,
            title: "示例",
            fireDate: fireDate
        )
    }

    @Test("标识按服务与业务键稳定生成，非法字符被清理")
    func identifierIsStable() {
        #expect(anchor(key: "17").identifier == "zm.qiansi.anniversary.17")
        #expect(anchor(key: "a b/c.d").identifier == "zm.qiansi.anniversary.a-b-c-d")
        #expect(anchor(key: "a b/c.d").identifier == anchor(key: "a b/c.d").identifier)
    }

    @Test("备注里嵌标记：空备注只留标记，有备注则追加一行")
    func markerEmbedding() {
        let plain = SystemAnchorMarker.embed("zm.a.b.c", in: nil)
        #expect(plain == "zm-anchor:zm.a.b.c")

        let withNotes = anchor()
        var copy = withNotes
        copy.notes = "正文"
        #expect(copy.markedNotes == "正文\nzm-anchor:zm.qiansi.anniversary.17")

        // 提醒事项没有 url 字段，深链必须跟着备注一起写进去。
        copy.url = URL(string: "zhongmiao://service/qiansi?target=anniversary&id=17")
        #expect(
            copy.markedNotes
                == "正文\nzhongmiao://service/qiansi?target=anniversary&id=17\nzm-anchor:zm.qiansi.anniversary.17"
        )
        #expect(SystemAnchorMarker.extract(from: copy.markedNotes) == copy.identifier)
    }

    @Test("从备注取回标记：多行、无标记、空值都正确")
    func markerExtraction() {
        #expect(SystemAnchorMarker.extract(from: "正文\nzm-anchor:zm.a.b.c") == "zm.a.b.c")
        #expect(SystemAnchorMarker.extract(from: "没有标记") == nil)
        #expect(SystemAnchorMarker.extract(from: nil) == nil)
        // 用户在日历里自己加了内容，标记被挤到中间也要能认出来。
        #expect(SystemAnchorMarker.extract(from: "前面\nZm-Anchor:zm.a.b.c") == nil)
    }

    @Test("全天与每年重复走日历，明确时刻走提醒事项")
    func channelSelection() {
        var yearly = anchor()
        yearly.repeatsYearly = true
        #expect(yearly.channel == .calendar)

        var allDay = anchor()
        allDay.isAllDay = true
        #expect(allDay.channel == .calendar)

        #expect(anchor().channel == .reminder)
    }

    @Test("从本地提醒转锚点：解析四段 id 并带上深链")
    func convertFromReminder() {
        guard let serviceID = ServiceCatalog.all.first?.id else {
            Issue.record("注册表为空")
            return
        }
        let id = IntegrationReminderID.make(
            serviceID: serviceID,
            kind: "event",
            key: "42",
            date: now
        )
        let reminder = PlannedReminder(
            id: id,
            serviceID: serviceID,
            title: "标题",
            body: "正文",
            fireDate: now,
            target: NativeTarget(kind: "event", identifier: "42")
        )
        let converted = SystemAnchor(reminder: reminder)
        #expect(converted?.serviceID == serviceID)
        #expect(converted?.kind == "event")
        #expect(converted?.key == "42")
        #expect(converted?.url == DeepLink.url(serviceID: serviceID, target: reminder.target))
        #expect(converted?.channel == .reminder)
    }

    @Test("生日/纪念日默认转成年度日历项，农历保持一次性提醒")
    func yearlyInference() {
        let id = IntegrationReminderID.make(
            serviceID: "qiansi",
            kind: "anniversary",
            key: "42",
            date: now
        )
        let annual = PlannedReminder(
            id: id,
            serviceID: "qiansi",
            title: "纪念日",
            body: "还有 30 天",
            fireDate: now,
            userInfo: ["kind": "anniversary", "id": "42"]
        )
        let converted = SystemAnchor(reminder: annual)
        #expect(converted?.repeatsYearly == true)
        #expect(converted?.channel == .calendar)

        var lunar = annual
        lunar.userInfo["repeatsYearly"] = "0"
        let lunarAnchor = SystemAnchor(reminder: lunar)
        #expect(lunarAnchor?.repeatsYearly == false)
        #expect(lunarAnchor?.channel == .reminder)
    }

    @Test("不是约定格式的 id 转不成锚点")
    func rejectsForeignID() {
        let reminder = PlannedReminder(
            id: "show.abc",
            serviceID: "mujian",
            title: "标题",
            body: "正文",
            fireDate: now
        )
        #expect(SystemAnchor(reminder: reminder) == nil)
    }

    @Test("预算：过期剔除、同标识去重、按服务与总量截断")
    func budgetTrims() {
        let future = Date(timeIntervalSince1970: 1_700_200_000)
        var expired = anchor(key: "old")
        expired = SystemAnchor(
            serviceID: "qiansi", kind: "anniversary", key: "old",
            title: "过期", fireDate: Date(timeIntervalSince1970: 1_600_000_000)
        )
        let kept = SystemAnchorBudget.apply(to: [expired, anchor(key: "a"), anchor(key: "a")], now: now)
        #expect(kept.count == 1)
        #expect(kept.first?.key == "a")

        // 每应用上限：同一服务堆 70 条，只留 60 条。
        let many = (0..<70).map { anchor(key: "k\($0)", fireDate: future) }
        #expect(SystemAnchorBudget.apply(to: many, now: now).count == SystemAnchorBudget.perServiceLimit)

        // 总量上限：四个服务各被压到 60 条（240），再被总量截到 200。
        let mixed = ["qiansi", "qingye", "shenshi", "diarum"].flatMap { serviceID in
            (0..<70).map { anchor(serviceID: serviceID, key: "k\($0)", fireDate: future) }
        }
        #expect(SystemAnchorBudget.apply(to: mixed, now: now).count == SystemAnchorBudget.totalLimit)
    }
}
