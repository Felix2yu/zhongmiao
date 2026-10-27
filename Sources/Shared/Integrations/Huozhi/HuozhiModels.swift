import Foundation

struct HuozhiUser: Codable, Hashable, Sendable {
    var id: Int
    var username: String
    var nickname: String?
    var currency: String?
    var defaultBookID: Int?

    enum CodingKeys: String, CodingKey {
        case id, username, nickname, currency
        case defaultBookID = "default_book_id"
    }
}

struct HuozhiBook: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var icon: String?
    var color: String?
    var currency: String?
    var isDefault: Bool?
    var isArchived: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, currency
        case isDefault = "is_default"
        case isArchived = "is_archived"
    }
}

struct HuozhiAccount: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var type: String
    var currency: String?
    var balance: Double
    var creditLimit: Double?
    var billDay: Int?
    var repayDay: Int?
    var includeInTotal: Bool?
    var includeInBudget: Bool?
    var isArchived: Bool?
    var isHidden: Bool?
    var bankName: String?
    var cardNo4: String?
    var remark: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, currency, balance, remark
        case creditLimit = "credit_limit"
        case billDay = "bill_day"
        case repayDay = "repay_day"
        case includeInTotal = "include_in_total"
        case includeInBudget = "include_in_budget"
        case isArchived = "is_archived"
        case isHidden = "is_hidden"
        case bankName = "bank_name"
        case cardNo4 = "card_no4"
    }

    var isCredit: Bool { type == "credit" || type == "liability" }
}

struct HuozhiAccountSummary: Codable, Hashable, Sendable {
    var totalAsset: Double?
    var totalDebt: Double?
    var netAsset: Double?
    var cashFlow: Double?

    enum CodingKeys: String, CodingKey {
        case totalAsset = "total_asset"
        case totalDebt = "total_debt"
        case netAsset = "net_asset"
        case cashFlow = "cash_flow"
    }
}

struct HuozhiAccountsResponse: Codable, Hashable, Sendable {
    var accounts: [HuozhiAccount]
    var summary: HuozhiAccountSummary?
}

struct HuozhiCategory: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var parentId: Int?
    var name: String
    var kind: String?
    var icon: String?
    var color: String?
    var isSystem: Bool?
    var isArchived: Bool?
    var isHidden: Bool?
    var children: [HuozhiCategory]?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, icon, color, children
        case parentId = "parent_id"
        case isSystem = "is_system"
        case isArchived = "is_archived"
        case isHidden = "is_hidden"
    }
}

struct HuozhiCategoryTree: Codable, Hashable, Sendable {
    var expense: [HuozhiCategory]
    var income: [HuozhiCategory]
    var system: [HuozhiCategory]

    func flattened(kind: String) -> [(category: HuozhiCategory, depth: Int)] {
        let roots = kind == "income" ? income : expense
        var result: [(HuozhiCategory, Int)] = []
        func walk(_ nodes: [HuozhiCategory], depth: Int) {
            for node in nodes {
                guard node.isArchived != true else { continue }
                result.append((node, depth))
                if let children = node.children {
                    walk(children, depth: depth + 1)
                }
            }
        }
        walk(roots, depth: 0)
        return result
    }
}

struct HuozhiAssetOverview: Codable, Hashable, Sendable {
    var totalAsset: Double?
    var totalDebt: Double?
    var netAsset: Double?
    var cashOnHand: Double?
    var monthIncome: Double?
    var monthExpense: Double?
    var monthNet: Double?
    var accountCount: Int?

    enum CodingKeys: String, CodingKey {
        case totalAsset = "total_asset"
        case totalDebt = "total_debt"
        case netAsset = "net_asset"
        case cashOnHand = "cash_on_hand"
        case monthIncome = "month_income"
        case monthExpense = "month_expense"
        case monthNet = "month_net"
        case accountCount = "account_count"
    }
}

struct HuozhiCreditCard: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var bankName: String?
    var cardNo4: String?
    var repayDay: Int?
    var billDay: Int?
    var balance: Double
    var creditLimit: Double?
    var daysLeft: Int?
    var repayDate: String?
    var billAmount: Double?
    var overdue: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, balance, overdue
        case bankName = "bank_name"
        case cardNo4 = "card_no4"
        case repayDay = "repay_day"
        case billDay = "bill_day"
        case creditLimit = "credit_limit"
        case daysLeft = "days_left"
        case repayDate = "repay_date"
        case billAmount = "bill_amount"
    }
}

struct HuozhiTag: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var color: String?
}

struct HuozhiTransaction: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var type: String
    var amount: Double
    var currency: String?
    var categoryId: Int?
    var categoryName: String?
    var accountId: Int?
    var accountName: String?
    var toAccountId: Int?
    var toAccountName: String?
    var txDate: String
    var description: String?
    var merchant: String?
    var remark: String?
    var tags: [HuozhiTag]?

    enum CodingKeys: String, CodingKey {
        case id, type, amount, currency, description, merchant, remark, tags
        case categoryId = "category_id"
        case categoryName = "category_name"
        case accountId = "account_id"
        case accountName = "account_name"
        case toAccountId = "to_account_id"
        case toAccountName = "to_account_name"
        case txDate = "tx_date"
    }

    var day: String {
        String(txDate.prefix(10))
    }

    var isExpenseLike: Bool { type == "expense" || type == "reimburse" }
    var isIncomeLike: Bool { type == "income" || type == "refund" }
}

struct HuozhiDayGroup: Codable, Hashable, Sendable, Identifiable {
    var date: String
    var dayIncome: Double?
    var dayExpense: Double?
    var dayBalance: Double?
    var transactions: [HuozhiTransaction]

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, transactions
        case dayIncome = "day_income"
        case dayExpense = "day_expense"
        case dayBalance = "day_balance"
    }
}

struct HuozhiPeriodSummary: Codable, Hashable, Sendable {
    var totalIncome: Double?
    var totalExpense: Double?
    var net: Double?

    enum CodingKeys: String, CodingKey {
        case totalIncome = "total_income"
        case totalExpense = "total_expense"
        case net
    }
}

struct HuozhiTransactionPage: Codable, Hashable, Sendable {
    var grouped: [HuozhiDayGroup]
    var summary: HuozhiPeriodSummary?
}

struct HuozhiSnapshot: Codable, Sendable {
    var user: HuozhiUser?
    var books: [HuozhiBook]
    var selectedBookID: Int?
    var accounts: [HuozhiAccount]
    var accountSummary: HuozhiAccountSummary?
    var categories: HuozhiCategoryTree
    var assets: HuozhiAssetOverview?
    var creditCards: [HuozhiCreditCard]
    var transactions: HuozhiTransactionPage
}

enum HuozhiDate {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw) {
                return date
            }
            if let date = dateOnlyFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析货殖时间：\(raw)"
            )
        }
        return decoder
    }()

    static func decimal(from amount: Double) -> Decimal {
        Decimal(string: String(format: "%.2f", amount), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
