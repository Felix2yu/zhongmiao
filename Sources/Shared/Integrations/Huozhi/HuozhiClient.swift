import Foundation
import ZhongmiaoCore

struct HuozhiClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, jwt: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: jwt)
    }

    func me() async throws -> HuozhiUser {
        try await get("/auth/me")
    }

    func books() async throws -> [HuozhiBook] {
        let data = try await payload("/books")
        if let list = try? JSONDecoder().decode([HuozhiBook].self, from: data) {
            return list
        }
        if let object = try? JSONDecoder().decode([String: [HuozhiBook]].self, from: data) {
            return object["books"] ?? object.values.first ?? []
        }
        throw IntegrationAPIError.decoding("货殖账本列表")
    }

    func accounts(bookID: Int) async throws -> HuozhiAccountsResponse {
        try await get("/accounts", query: [URLQueryItem(name: "book_id", value: String(bookID))])
    }

    func categories(bookID: Int) async throws -> HuozhiCategoryTree {
        try await get("/categories", query: [URLQueryItem(name: "book_id", value: String(bookID))])
    }

    func assets(bookID: Int) async throws -> HuozhiAssetOverview {
        try await get("/statistics/assets", query: [URLQueryItem(name: "book_id", value: String(bookID))])
    }

    func transactions(bookID: Int, pageSize: Int = 20) async throws -> HuozhiTransactionPage {
        let data = try await payload(
            "/transactions",
            query: [
                URLQueryItem(name: "book_id", value: String(bookID)),
                URLQueryItem(name: "page_size", value: String(pageSize))
            ]
        )
        do {
            let raw = try HuozhiDate.decoder.decode(RawTransactionPage.self, from: data)
            return HuozhiTransactionPage(
                grouped: raw.list?.grouped ?? raw.grouped ?? [],
                summary: raw.list?.summary ?? raw.summary
            )
        } catch {
            throw IntegrationAPIError.decoding("货殖流水：\(error.localizedDescription)")
        }
    }

    private struct RawTransactionPage: Decodable {
        struct List: Decodable {
            var grouped: [HuozhiDayGroup]
            var summary: HuozhiPeriodSummary?
        }

        var list: List?
        var grouped: [HuozhiDayGroup]?
        var summary: HuozhiPeriodSummary?
    }

    func creditSummary() async throws -> [HuozhiCreditCard] {
        let data = try await payload("/accounts/credit-summary")
        if let list = try? HuozhiDate.decoder.decode([HuozhiCreditCard].self, from: data) {
            return list
        }
        if let object = try? HuozhiDate.decoder.decode([String: [HuozhiCreditCard]].self, from: data) {
            return object["cards"] ?? object.values.first ?? []
        }
        if data == Data("null".utf8) { return [] }
        throw IntegrationAPIError.decoding("货殖信用卡摘要")
    }

    func create(_ draft: HuozhiDraft, currency: String?) async throws -> HuozhiTransaction {
        let body = try JSONEncoder().encode(
            CreateBody(
                book_id: draft.bookID,
                type: draft.kind.isTransfer ? "transfer" : draft.kind.rawValue,
                amount: NSDecimalNumber(decimal: draft.amount).doubleValue,
                account_id: draft.accountID,
                to_account_id: draft.kind.isTransfer ? draft.toAccountID : nil,
                category_id: draft.kind.isTransfer ? nil : (draft.categoryID > 0 ? draft.categoryID : nil),
                tx_date: draft.date,
                description: draft.note,
                currency: currency,
                include_in_balance: true,
                include_in_budget: true
            )
        )
        let data = try await http.data("/transactions", method: "POST", body: body)
        let payload = try IntegrationEnvelope.unwrapCode(data)
        do {
            return try HuozhiDate.decoder.decode(HuozhiTransaction.self, from: payload)
        } catch {
            throw IntegrationAPIError.decoding("货殖记账响应：\(error.localizedDescription)")
        }
    }

    private struct CreateBody: Encodable {
        let book_id: Int
        let type: String
        let amount: Double
        let account_id: Int
        let to_account_id: Int?
        let category_id: Int?
        let tx_date: String
        let description: String
        let currency: String?
        let include_in_balance: Bool
        let include_in_budget: Bool
    }

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        let data = try await payload(path, query: query)
        do {
            return try HuozhiDate.decoder.decode(T.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("货殖 \(path)：\(error.localizedDescription)")
        }
    }

    private func payload(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        let data = try await http.data(path, query: query)
        return try IntegrationEnvelope.unwrapCode(data)
    }
}
