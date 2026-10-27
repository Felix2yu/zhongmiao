import Testing
import Foundation

@testable import ZhongmiaoCore

@Suite("原生条目深链")
struct NativeTargetTests {

    @Test("提醒会自己把目标写进 userInfo")
    func reminderCarriesTarget() {
        let reminder = PlannedReminder(
            id: "integration.mujian.record.1.20261027",
            serviceID: "mujian",
            title: "演出提醒",
            body: "明天 18:12 晚霞剧场",
            fireDate: Date(timeIntervalSince1970: 1_800_000_000),
            target: NativeTarget(kind: "record", identifier: "1F835496")
        )
        #expect(reminder.userInfo[NativeTargetKeys.kind] == "record")
        #expect(reminder.userInfo[NativeTargetKeys.identifier] == "1F835496")
        #expect(reminder.target?.identifier == "1F835496")
    }

    @Test("没有目标时不写多余的键")
    func noTargetLeavesUserInfoAlone() {
        let reminder = PlannedReminder(
            id: "integration.qingye.care.20261027",
            serviceID: "qingye",
            title: "今日养护",
            body: "给绿萝浇水",
            fireDate: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(reminder.userInfo[NativeTargetKeys.kind] == nil)
        #expect(reminder.target == nil)
    }

    @Test("userInfo 里能还原出目标")
    func restoreFromUserInfo() {
        let info: [AnyHashable: Any] = [
            NativeTargetKeys.kind: "plant",
            NativeTargetKeys.identifier: "42"
        ]
        let target = NativeTargetKeys.target(from: info)
        #expect(target == NativeTarget(kind: "plant", identifier: "42"))
    }

    @Test("键缺失或为空时视为没有目标")
    func incompleteUserInfoHasNoTarget() {
        #expect(NativeTargetKeys.target(from: [:]) == nil)
        #expect(NativeTargetKeys.target(from: [NativeTargetKeys.kind: "plant"]) == nil)
        #expect(NativeTargetKeys.target(from: [NativeTargetKeys.kind: "", NativeTargetKeys.identifier: "42"]) == nil)
    }

    @Test("带目标的深链走原生页")
    func targetPrefersNative() {
        #expect(
            IntegrationRouter.resolve(
                serviceID: "mujian",
                hasExplicitURL: false,
                preferWeb: false,
                hasNativeTarget: true
            ) == .native
        )
    }

    @Test("用户显式选网页版时不抢")
    func preferWebStillWins() {
        #expect(
            IntegrationRouter.resolve(
                serviceID: "mujian",
                hasExplicitURL: false,
                preferWeb: true,
                hasNativeTarget: true
            ) == .web
        )
    }

    @Test("网页版应用即使带目标也走网页")
    func webOnlyIgnoresTarget() {
        #expect(
            IntegrationRouter.resolve(
                serviceID: "whoami",
                hasExplicitURL: false,
                preferWeb: false,
                hasNativeTarget: true
            ) == .web
        )
    }
}
