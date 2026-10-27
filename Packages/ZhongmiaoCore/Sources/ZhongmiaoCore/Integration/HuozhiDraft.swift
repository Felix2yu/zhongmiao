import Foundation

/// 货殖没有幂等键，写请求超时后不能自动重发。
/// 这个状态机把“已提交但不知道结果”显式建模出来，界面据此进入核对流程。
public enum HuozhiDraftState: String, Sendable, Codable {
    case draft
    case submitting
    case confirmed
    case unknown
}

public enum HuozhiEntryKind: String, Sendable, CaseIterable, Codable, Identifiable {
    case expense
    case income
    case transfer
    case repayment

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        case .repayment: "还款"
        }
    }

    public var isTransfer: Bool {
        self == .transfer || self == .repayment
    }
}

public enum HuozhiDraftError: Error, Sendable, Equatable, LocalizedError {
    case invalidAmount
    case missingBook
    case missingAccount
    case missingToAccount
    case sameAccount

    public var errorDescription: String? {
        switch self {
        case .invalidAmount: "金额必须大于 0"
        case .missingBook: "请选择账本"
        case .missingAccount: "请选择账户"
        case .missingToAccount: "请选择转入/还款账户"
        case .sameAccount: "转出与转入账户不能相同"
        }
    }
}

public struct HuozhiDraft: Sendable, Equatable {

    public var kind: HuozhiEntryKind
    public var amount: Decimal
    public var bookID: Int
    public var accountID: Int
    public var toAccountID: Int?
    public var categoryID: Int
    public var date: String
    public var note: String
    public var state: HuozhiDraftState

    public init(
        kind: HuozhiEntryKind,
        amount: Decimal = 0,
        bookID: Int = 0,
        accountID: Int = 0,
        toAccountID: Int? = nil,
        categoryID: Int = 0,
        date: String,
        note: String = "",
        state: HuozhiDraftState = .draft
    ) {
        self.kind = kind
        self.amount = amount
        self.bookID = bookID
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.categoryID = categoryID
        self.date = date
        self.note = note
        self.state = state
    }

    public var canSubmit: Bool { state == .draft }
    public var needsReconciliation: Bool { state == .unknown }

    public func validated() throws -> HuozhiDraft {
        guard amount > 0 else { throw HuozhiDraftError.invalidAmount }
        guard bookID > 0 else { throw HuozhiDraftError.missingBook }
        guard accountID > 0 else { throw HuozhiDraftError.missingAccount }
        if kind.isTransfer {
            guard let toAccountID, toAccountID > 0 else { throw HuozhiDraftError.missingToAccount }
            guard toAccountID != accountID else { throw HuozhiDraftError.sameAccount }
        }
        return self
    }

    public mutating func beginSubmit() {
        guard canSubmit else { return }
        state = .submitting
    }

    public mutating func confirm() {
        state = .confirmed
    }

    public mutating func markUnknown() {
        state = .unknown
    }

    /// 只有核对确认“服务端没有这笔”之后，用户才能手动重试。
    public mutating func allowResubmit() {
        guard state == .unknown else { return }
        state = .draft
    }
}

/// 核对用的最小流水投影。
public struct HuozhiReconcileCandidate: Sendable, Equatable {

    public var id: Int
    public var amount: Decimal
    public var accountID: Int
    public var toAccountID: Int?
    public var day: String
    public var note: String

    public init(
        id: Int,
        amount: Decimal,
        accountID: Int,
        toAccountID: Int?,
        day: String,
        note: String
    ) {
        self.id = id
        self.amount = amount
        self.accountID = accountID
        self.toAccountID = toAccountID
        self.day = day
        self.note = note
    }
}

extension HuozhiDraft {

    /// 金额、账户、日期必须一致；备注两边都有内容时要求互相包含。
    public func matches(_ candidate: HuozhiReconcileCandidate) -> Bool {
        guard amount == candidate.amount else { return false }
        guard accountID == candidate.accountID else { return false }
        guard date == candidate.day else { return false }
        if kind.isTransfer {
            guard toAccountID == candidate.toAccountID else { return false }
        }
        let lhs = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = candidate.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if lhs.isEmpty || rhs.isEmpty { return true }
        return lhs == rhs || rhs.contains(lhs) || lhs.contains(rhs)
    }
}
