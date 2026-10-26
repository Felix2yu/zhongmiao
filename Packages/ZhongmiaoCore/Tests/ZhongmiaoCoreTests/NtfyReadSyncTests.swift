import Foundation
import Testing

@testable import ZhongmiaoCore

/// 已读状态同步：服务端广播的 `message_clear` 要能落到本地条目上，
/// 本地标记的已读也要能按服务端认可的 id 推回去。
@Suite("ntfy 已读同步")
struct NtfyReadSyncTests {

    private func item(
        _ id: String,
        sequenceID: String? = nil,
        messageID: String? = nil,
        serviceID: String = "ntfy:ops"
    ) -> NotificationItem {
        NotificationItem(
            id: "\(serviceID)#\(id)",
            serviceID: serviceID,
            title: "磁盘告警",
            body: "使用率 91%",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: .ntfy,
            ntfyMessageID: messageID,
            ntfySequenceID: sequenceID,
            ntfyTopic: "ops"
        )
    }

    // MARK: - 服务端 → 本地

    @Test("按序列 id 命中服务端广播的已读")
    func marksReadBySequenceID() {
        var ledger = NotificationLedger()
        ledger.merge([item("a", sequenceID: "seq-a", messageID: "msg-a")])
        #expect(ledger.markRead(ntfyTargets: ["seq-a"], serviceID: "ntfy:ops") == 1)
        #expect(ledger.unreadCount == 0)
    }

    @Test("服务端用消息 id 寻址时同样命中")
    func marksReadByMessageID() {
        var ledger = NotificationLedger()
        ledger.merge([item("b", messageID: "msg-b")])
        #expect(ledger.markRead(ntfyTargets: ["msg-b"], serviceID: "ntfy:ops") == 1)
        #expect(ledger.unreadCount == 0)
    }

    @Test("只影响对应服务的条目")
    func isolatesService() {
        var ledger = NotificationLedger()
        ledger.merge([item("c", messageID: "msg-c")])
        #expect(ledger.markRead(ntfyTargets: ["msg-c"], serviceID: "ntfy:other") == 0)
        #expect(ledger.unreadCount == 1)
    }

    @Test("同一条广播重复到达不会重复计数")
    func idempotentBroadcast() {
        var ledger = NotificationLedger()
        ledger.merge([item("d", messageID: "msg-d")])
        #expect(ledger.markRead(ntfyTargets: ["msg-d"], serviceID: "ntfy:ops") == 1)
        #expect(ledger.markRead(ntfyTargets: ["msg-d"], serviceID: "ntfy:ops") == 0)
    }

    @Test("没有对应条目的广播不产生噪音")
    func ignoresUnknownTargets() {
        var ledger = NotificationLedger()
        ledger.merge([item("e", messageID: "msg-e")])
        #expect(ledger.markRead(ntfyTargets: ["msg-z"], serviceID: "ntfy:ops") == 0)
        #expect(ledger.markRead(ntfyTargets: [], serviceID: "ntfy:ops") == 0)
        #expect(ledger.unreadCount == 1)
    }

    // MARK: - 本地 → 服务端

    @Test("动作 id 必须符合服务端的形式")
    func validatesActionIDs() {
        #expect(NtfyActionID.isValid("abcDEF-_123"))
        #expect(NtfyActionID.isValid(String(repeating: "a", count: 64)))
        #expect(!NtfyActionID.isValid(""))
        #expect(!NtfyActionID.isValid("a b"))
        #expect(!NtfyActionID.isValid("a/b"))
        #expect(!NtfyActionID.isValid(String(repeating: "a", count: 65)))
    }

    @Test("目标 id 优先用序列 id")
    func targetPrefersSequenceID() {
        #expect(NtfyActionID.targetID(sequenceID: "seq", messageID: "msg") == "seq")
        #expect(NtfyActionID.targetID(sequenceID: nil, messageID: "msg") == "msg")
        #expect(NtfyActionID.targetID(sequenceID: "", messageID: "msg") == "msg")
        #expect(NtfyActionID.targetID(sequenceID: nil, messageID: nil) == nil)
        // 序列 id 不合法时退回消息 id，而不是整条丢弃。
        #expect(NtfyActionID.targetID(sequenceID: "bad id", messageID: "msg") == "msg")
    }

    @Test("非法与重复的 id 不进批量请求")
    func chunksDropInvalidIDs() {
        let chunks = NtfyActionID.chunks(["a", "b b", "c", "a"], limit: 2)
        #expect(chunks == [["a", "c"]])
    }

    @Test("批量请求按 50 个一批切分")
    func chunksRespectLimit() {
        let ids = (1...120).map { "id\($0)" }
        let chunks = NtfyActionID.chunks(ids)
        #expect(chunks.count == 3)
        #expect(chunks[0].count == 50)
        #expect(chunks[1].count == 50)
        #expect(chunks[2].count == 20)
    }

    @Test("条目能给出回推服务端用的目标 id")
    func itemExposesTargetID() {
        let withSequence = item("f", sequenceID: "seq-f", messageID: "msg-f")
        #expect(withSequence.ntfyTargetID == "seq-f")
        let withoutSequence = item("g", messageID: "msg-g")
        #expect(withoutSequence.ntfyTargetID == "msg-g")
        let plain = NotificationItem(
            id: "shenshi#x",
            serviceID: "shenshi",
            title: "标题",
            body: "正文",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(plain.ntfyTargetID == nil)
    }
}
