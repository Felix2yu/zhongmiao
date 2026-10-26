import Foundation
import Testing
@testable import ZhongmiaoCore

struct NtfyTopicTests {

    @Test func serviceIDRoundTrip() {
        let id = NtfyTopic.serviceID(for: "build-alerts")
        #expect(id == "ntfy:build-alerts")
        #expect(NtfyTopic.topic(fromServiceID: id) == "build-alerts")
        #expect(NtfyTopic.isStandaloneServiceID(id))
    }

    @Test func plainServiceIDsAreNotStandalone() {
        #expect(NtfyTopic.topic(fromServiceID: "shenshi") == nil)
        #expect(NtfyTopic.topic(fromServiceID: "ntfy") == nil)
        #expect(!NtfyTopic.isStandaloneServiceID("shenshi"))
        #expect(NtfyTopic.topic(fromServiceID: "ntfy:") == nil)
    }

    @Test func normalizesWhitespace() {
        #expect(NtfyTopic.normalized("  alerts \n") == "alerts")
        #expect(NtfyTopic.normalized("   ") == nil)
    }

    @Test func rejectsIllegalCharacters() {
        #expect(NtfyTopic.normalized("a/b") == nil)
        #expect(NtfyTopic.normalized("has space") == nil)
        #expect(NtfyTopic.normalized("中文主题") == nil)
        #expect(NtfyTopic.normalized("emoji🎉") == nil)
    }

    @Test func acceptsAllowedAlphabet() {
        #expect(NtfyTopic.normalized("Build_2026-10") == "Build_2026-10")
        #expect(NtfyTopic.normalized("-") == "-")
        #expect(NtfyTopic.normalized("_") == "_")
    }

    @Test func enforcesLength() {
        let longest = String(repeating: "a", count: NtfyTopic.maximumLength)
        #expect(NtfyTopic.isValid(longest))
        #expect(!NtfyTopic.isValid(longest + "a"))
    }

    @Test func validationMessages() {
        #expect(NtfyTopic.validationMessage(for: "") != nil)
        #expect(NtfyTopic.validationMessage(for: "a b") != nil)
        #expect(NtfyTopic.validationMessage(for: "alerts") == nil)
    }

    @Test func dedupeKeysDifferPerTopic() {
        let first = NotificationItem.makeID(
            serviceID: NtfyTopic.serviceID(for: "a"),
            eventID: "abc",
            title: "t",
            body: "b",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let second = NotificationItem.makeID(
            serviceID: NtfyTopic.serviceID(for: "b"),
            eventID: "abc",
            title: "t",
            body: "b",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        #expect(first != second)
    }
}
