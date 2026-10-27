import Foundation
import Testing

@testable import ZhongmiaoCore

@Suite("货殖记账草稿")
struct HuozhiDraftTests {

    private func draft(
        kind: HuozhiEntryKind = .expense,
        amount: String = "12.34",
        toAccountID: Int? = nil
    ) -> HuozhiDraft {
        HuozhiDraft(
            kind: kind,
            amount: Decimal(string: amount)!,
            bookID: 1,
            accountID: 2,
            toAccountID: toAccountID,
            categoryID: 3,
            date: "2026-10-27",
            note: "午餐"
        )
    }

    @Test("合法支出通过校验")
    func validExpense() throws {
        _ = try draft().validated()
    }

    @Test("金额必须大于 0")
    func invalidAmount() {
        #expect(throws: HuozhiDraftError.invalidAmount) {
            try draft(amount: "0").validated()
        }
    }

    @Test("转账必须有不同转入账户")
    func transferNeedsTarget() {
        #expect(throws: HuozhiDraftError.missingToAccount) {
            try draft(kind: .transfer).validated()
        }
        #expect(throws: HuozhiDraftError.sameAccount) {
            try draft(kind: .transfer, toAccountID: 2).validated()
        }
        #expect(throws: Never.self) {
            try draft(kind: .transfer, toAccountID: 4).validated()
        }
    }

    @Test("提交状态机：未知时禁止重发，核对后才可重试")
    func stateMachine() {
        var value = draft()
        #expect(value.canSubmit)
        value.beginSubmit()
        #expect(value.state == .submitting)
        value.markUnknown()
        #expect(value.needsReconciliation)
        #expect(!value.canSubmit)
        value.beginSubmit()
        #expect(value.state == .unknown)
        value.allowResubmit()
        #expect(value.canSubmit)
        value.beginSubmit()
        value.confirm()
        #expect(value.state == .confirmed)
        #expect(!value.canSubmit)
    }

    @Test("超时核对按金额、账户、日期、备注匹配")
    func reconcile() {
        let value = draft()
        let matched = HuozhiReconcileCandidate(
            id: 9,
            amount: Decimal(string: "12.34")!,
            accountID: 2,
            toAccountID: nil,
            day: "2026-10-27",
            note: "午餐 · 快餐"
        )
        #expect(value.matches(matched))

        let wrongAmount = HuozhiReconcileCandidate(
            id: 10,
            amount: Decimal(string: "12.35")!,
            accountID: 2,
            toAccountID: nil,
            day: "2026-10-27",
            note: "午餐"
        )
        #expect(!value.matches(wrongAmount))

        let wrongDay = HuozhiReconcileCandidate(
            id: 11,
            amount: Decimal(string: "12.34")!,
            accountID: 2,
            toAccountID: nil,
            day: "2026-10-28",
            note: "午餐"
        )
        #expect(!value.matches(wrongDay))
    }

    @Test("转账核对要求目标账户一致")
    func reconcileTransfer() {
        let value = draft(kind: .transfer, toAccountID: 4)
        let matched = HuozhiReconcileCandidate(
            id: 1,
            amount: Decimal(string: "12.34")!,
            accountID: 2,
            toAccountID: 4,
            day: "2026-10-27",
            note: "午餐"
        )
        #expect(value.matches(matched))
        let wrongTarget = HuozhiReconcileCandidate(
            id: 2,
            amount: Decimal(string: "12.34")!,
            accountID: 2,
            toAccountID: 5,
            day: "2026-10-27",
            note: "午餐"
        )
        #expect(!value.matches(wrongTarget))
    }
}
