import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("ntfy 协议")
struct NtfyTests {

    @Test("解析单行 JSON")
    func decodesLine() throws {
        let line = #"{"id":"abc","time":1700000000,"event":"message","topic":"ops","title":"部署完成","message":"shenshi v1.2.3","priority":4,"click":"https://shenshi.example.com/tasks/42"}"#
        let message = try #require(NtfyStreamDecoder.decode(line: line))
        #expect(message.id == "abc")
        #expect(message.topic == "ops")
        #expect(message.priority == 4)
        #expect(message.isDeliverable)
    }

    @Test("keepalive 与 open 不算消息")
    func filtersControlEvents() {
        let keepalive = #"{"id":"x","time":1700000000,"event":"keepalive","topic":"ops"}"#
        let open = #"{"id":"y","time":1700000000,"event":"open","topic":"ops"}"#
        #expect(NtfyStreamDecoder.decode(line: keepalive)?.isDeliverable == false)
        #expect(NtfyStreamDecoder.decode(line: open)?.isDeliverable == false)
        #expect(NtfyStreamDecoder.decode(line: keepalive)?.notificationItem(serviceID: "ntfy") == nil)
    }

    @Test("空内容与非法行被忽略")
    func ignoresInvalid() {
        #expect(NtfyStreamDecoder.decode(line: "") == nil)
        #expect(NtfyStreamDecoder.decode(line: "not json") == nil)
        #expect(NtfyStreamDecoder.decode(line: #"{"event":"message","topic":"ops"}"#)?.isDeliverable == false)
    }

    @Test("优先级映射：1–2 静默，3 常规，4–5 时效")
    func priorityMapping() {
        #expect(NotificationItem.Priority.fromNtfy(1) == .passive)
        #expect(NotificationItem.Priority.fromNtfy(2) == .passive)
        #expect(NotificationItem.Priority.fromNtfy(3) == .active)
        #expect(NotificationItem.Priority.fromNtfy(nil) == .active)
        #expect(NotificationItem.Priority.fromNtfy(4) == .timeSensitive)
        #expect(NotificationItem.Priority.fromNtfy(5) == .timeSensitive)
    }

    @Test("转换后的条目带稳定的去重键与深链")
    func convertsToItem() throws {
        let message = NtfyMessage(
            id: "m1",
            time: 1_700_000_000,
            event: "message",
            topic: "ops",
            message: "磁盘使用率 91%",
            title: "告警",
            priority: 5,
            click: "https://ntfy.example.com/topic"
        )
        let converted = try #require(message.notificationItem(serviceID: "ntfy"))

        #expect(converted.id == "ntfy#m1")
        #expect(converted.source == .ntfy)
        #expect(converted.priority == .timeSensitive)
        #expect(converted.url?.absoluteString == "https://ntfy.example.com/topic")
        #expect(converted.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
        // 同一消息重复转换结果一致（去重前提）。
        #expect(converted.id == message.notificationItem(serviceID: "ntfy")?.id)
    }

    @Test("缺少 click 时回退到服务首页")
    func fallsBackToServiceURL() throws {
        let message = NtfyMessage(id: "m2", time: 1_700_000_000, event: "message", topic: "ops", message: "hi")
        let fallback = URL(string: "https://ntfy.example.com")!
        let converted = try #require(message.notificationItem(serviceID: "ntfy", fallbackURL: fallback))
        #expect(converted.url == fallback)
    }

    @Test("NDJSON 流式解析保留半行")
    func drainsStream() {
        var buffer = """
        {"id":"1","time":1700000000,"event":"message","topic":"a","message":"one"}
        {"id":"2","time":1700000001,"event":"message","topic":"a","message":"two"}
        {"id":"3","time":17000000
        """
        let messages = NtfyStreamDecoder.drain(buffer: &buffer)
        #expect(messages.count == 2)
        #expect(messages.map(\.id) == ["1", "2"])
        #expect(buffer.hasPrefix(#"{"id":"3""#))

        buffer += "02,\"event\":\"message\",\"message\":\"three\"}\n"
        #expect(NtfyStreamDecoder.drain(buffer: &buffer).count == 1)
        #expect(buffer.isEmpty)
    }

    @Test("since 参数向下取整避免漏事件")
    func sinceParameter() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.9)
        #expect(NtfyStreamDecoder.sinceParameter(date) == "1700000000")
    }
}

@Suite("通用通知流")
struct FeedTests {

    @Test("解析标准契约并映射优先级")
    func decodesContract() throws {
        let json = """
        {
          "items": [
            {"id":"e1","title":"构建完成","body":"耗时 42s","createdAt":"2026-10-24T05:00:00Z","url":"/builds/1","priority":"time-sensitive"},
            {"id":"e2","title":"新任务","createdAt":"2026-10-24T04:00:00.500Z","priority":"passive"}
          ],
          "nextCursor": "2026-10-24T05:00:00Z"
        }
        """.data(using: .utf8)!

        let page = try FeedParser.decode(json)
        #expect(page.items.count == 2)
        #expect(page.nextCursor == "2026-10-24T05:00:00Z")

        let base = URL(string: "https://shenshi.example.com")!
        let items = FeedParser.items(from: page, serviceID: "shenshi", baseURL: base)
        #expect(items.count == 2)
        #expect(items[0].priority == .timeSensitive)
        #expect(items[1].priority == .passive)
        #expect(items[0].url?.absoluteString == "https://shenshi.example.com/builds/1")
        #expect(items[0].source == .feed)
        #expect(items[0].id == "shenshi#e1")
    }

    @Test("标题为空的条目被丢弃")
    func dropsEmptyTitle() throws {
        let json = #"{"items":[{"id":"x","title":"   "},{"id":"y","title":"ok"}]}"#.data(using: .utf8)!
        let page = try FeedParser.decode(json)
        let items = FeedParser.items(from: page, serviceID: "shenshi", baseURL: nil)
        #expect(items.map(\.id) == ["shenshi#y"])
    }

    @Test("多种时间格式都能解析")
    func flexibleDates() {
        #expect(FlexibleDate.parse("2026-10-24T05:00:00Z") != nil)
        #expect(FlexibleDate.parse("2026-10-24T05:00:00.123Z") != nil)
        #expect(FlexibleDate.parse("2026-10-24 05:00:00") != nil)
        #expect(FlexibleDate.parse("1700000000") == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(FlexibleDate.parse("1700000000000") == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(FlexibleDate.parse("昨天") == nil)
    }
}

@Suite("重试策略")
struct RetryPolicyTests {

    @Test("无抖动时按指数增长并封顶")
    func exponentialGrowth() {
        let policy = RetryPolicy(base: 2, maximum: 30, multiplier: 2, jitter: 0)
        #expect(policy.delay(forAttempt: 1) == 2)
        #expect(policy.delay(forAttempt: 2) == 4)
        #expect(policy.delay(forAttempt: 3) == 8)
        #expect(policy.delay(forAttempt: 10) == 30)
        #expect(policy.delay(forAttempt: 0) == 2)
    }

    @Test("抖动落在允许区间内")
    func jitterBounds() {
        let policy = RetryPolicy(base: 10, maximum: 100, multiplier: 2, jitter: 0.5)
        #expect(policy.delay(forAttempt: 1, randomUnit: 0) == 5)
        #expect(policy.delay(forAttempt: 1, randomUnit: 1) == 10)
        let middle = policy.delay(forAttempt: 1, randomUnit: 0.5)
        #expect(middle > 5 && middle < 10)
    }

    @Test("达到次数上限后不再立即重试")
    func retryLimit() {
        let policy = RetryPolicy.standard
        #expect(policy.shouldRetry(attempt: 1))
        #expect(policy.shouldRetry(attempt: 5))
        #expect(!policy.shouldRetry(attempt: 6))
    }
}
