import Foundation
import Testing

@testable import ZhongmiaoCore

private func item(
    _ id: String,
    minutesAgo: Double = 0,
    read: Bool = false,
    service: String = "shenshi",
    delivered: Bool = false
) -> NotificationItem {
    NotificationItem(
        id: id,
        serviceID: service,
        title: "标题 \(id)",
        body: "正文",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000 - minutesAgo * 60),
        isRead: read,
        deliveredAt: delivered ? Date(timeIntervalSince1970: 1_700_000_100) : nil
    )
}

@Suite("通知账本")
struct NotificationLedgerTests {

    @Test("重复合并保持幂等")
    func mergeIsIdempotent() {
        var ledger = NotificationLedger()
        let batch = [item("a"), item("b"), item("c")]

        let first = ledger.merge(batch)
        #expect(first.inserted.count == 3)
        #expect(first.duplicateCount == 0)
        #expect(ledger.items.count == 3)

        let second = ledger.merge(batch)
        #expect(second.inserted.isEmpty)
        #expect(second.duplicateCount == 3)
        #expect(ledger.items.count == 3)
    }

    @Test("批内重复只保留一条")
    func deduplicatesWithinBatch() {
        var ledger = NotificationLedger()
        let result = ledger.merge([item("x"), item("x")])
        #expect(result.inserted.count == 1)
        #expect(result.duplicateCount == 1)
    }

    @Test("按时间升序返回待投递条目，便于顺序补发")
    func pendingDeliveryIsOrdered() {
        var ledger = NotificationLedger()
        ledger.merge([item("new", minutesAgo: 0), item("old", minutesAgo: 30), item("mid", minutesAgo: 10)])
        #expect(ledger.pendingDelivery.map(\.id) == ["old", "mid", "new"])
    }

    @Test("已投递条目不重复进入待投递队列")
    func deliveredItemsAreSkipped() {
        var ledger = NotificationLedger()
        ledger.merge([item("a"), item("b")])
        let firstMark = ledger.markDelivered(id: "a")
        #expect(firstMark)
        #expect(ledger.pendingDelivery.map(\.id) == ["b"])
        let missing = ledger.markDelivered(id: "missing")
        #expect(!missing)
    }

    @Test("合并新批次时清空历史已投递标记之外的状态")
    func mergeStampsReceivedAt() {
        var ledger = NotificationLedger()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let result = ledger.merge([item("a")], now: now)
        #expect(result.inserted.first?.receivedAt == now)
    }

    @Test("游标只前进不后退")
    func cursorIsMonotonic() {
        var ledger = NotificationLedger()
        let t1 = Date(timeIntervalSince1970: 1_700_000_000)
        let t2 = t1.addingTimeInterval(60)

        let firstAdvance = ledger.advanceCursor(serviceID: "shenshi", to: t1)
        #expect(firstAdvance)
        let backwards = ledger.advanceCursor(serviceID: "shenshi", to: t1.addingTimeInterval(-10))
        #expect(!backwards)
        let secondAdvance = ledger.advanceCursor(serviceID: "shenshi", to: t2)
        #expect(secondAdvance)
        #expect(ledger.cursor(for: "shenshi") == t2)
    }

    @Test("冷启动回看窗口默认一天")
    func fetchSinceFallsBackToLookback() {
        var ledger = NotificationLedger()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(ledger.fetchSince(serviceID: "ntfy", now: now) == now.addingTimeInterval(-86_400))

        ledger.advanceCursor(serviceID: "ntfy", to: now)
        #expect(ledger.fetchSince(serviceID: "ntfy", now: now) == now)
    }

    @Test("容量超限优先淘汰已读的最旧记录")
    func trimsOldestReadFirst() {
        var ledger = NotificationLedger(capacity: 50)
        let seeded = (0..<50).map { item("s\($0)", minutesAgo: Double(100 - $0), read: $0 >= 40) }
        ledger.merge(seeded)
        #expect(ledger.items.count == 50)

        ledger.merge((0..<5).map { item("n\($0)", minutesAgo: Double($0)) })
        #expect(ledger.items.count == 50)
        // 40 条未读 + 新增 5 条 = 45 条未读，被淘汰的 5 条都是已读。
        #expect(ledger.unreadCount == 45)
    }

    @Test("已读与清理")
    func readAndRemove() {
        var ledger = NotificationLedger()
        ledger.merge([item("a"), item("b", service: "ntfy")])
        ledger.markRead(id: "a")
        #expect(ledger.unreadCount == 1)
        ledger.markAllRead()
        #expect(ledger.unreadCount == 0)

        ledger.remove(serviceID: "ntfy")
        #expect(ledger.items.count == 1)
        ledger.remove()
        #expect(ledger.items.isEmpty)
        #expect(ledger.cursors.isEmpty)
    }

    @Test("编码解码保持容量与游标")
    func roundTrip() throws {
        var ledger = NotificationLedger(capacity: 120)
        ledger.merge([item("a")])
        ledger.advanceCursor(serviceID: "shenshi", to: Date(timeIntervalSince1970: 1_700_000_500))

        let data = try JSONEncoder().encode(ledger)
        let decoded = try JSONDecoder().decode(NotificationLedger.self, from: data)
        #expect(decoded.capacity == 120)
        #expect(decoded.items.count == 1)
        #expect(decoded.cursor(for: "shenshi") == Date(timeIntervalSince1970: 1_700_000_500))
    }
}
