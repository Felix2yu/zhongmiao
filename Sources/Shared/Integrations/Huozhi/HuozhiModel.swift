import Foundation
import Observation
import ZhongmiaoCore

struct HuozhiCategoryOption: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var depth: Int
}

@MainActor
@Observable
final class HuozhiModel {

    enum SubmitOutcome: Equatable {
        case saved(HuozhiTransaction)
        case unknown
        case failed(String)
    }

    let service: ServiceDefinition
    let baseURL: URL
    let center: IntegrationCenter

    private(set) var snapshot: HuozhiSnapshot?
    private(set) var selectedBookID: Int?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var error: String?

    init(service: ServiceDefinition, baseURL: URL, center: IntegrationCenter) {
        self.service = service
        self.baseURL = baseURL
        self.center = center
    }

    private func client(jwt: String) -> HuozhiClient {
        HuozhiClient(baseURL: baseURL, jwt: jwt)
    }

    // MARK: - 读取

    func loadCache() async {
        guard snapshot == nil else { return }
        if let cached = await center.cache.load(HuozhiSnapshot.self, serviceID: "huozhi") {
            snapshot = cached.payload
            selectedBookID = cached.payload.selectedBookID
            lastUpdated = cached.fetchedAt
        }
    }

    func refreshIfNeeded() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 120 { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        guard let jwt = center.credential(for: "huozhi")?.jwt, !jwt.isEmpty else { return }
        isLoading = true
        error = nil
        do {
            let value = try await withAuth { jwt -> HuozhiSnapshot in
                let client = client(jwt: jwt)
                let user = try await client.me()
                let books = try await client.books()
                guard !books.isEmpty else {
                    throw IntegrationAPIError.server(code: -1, message: "货殖没有可用账本")
                }

                let preferred = selectedBookID ?? snapshot?.selectedBookID ?? user.defaultBookID
                let book = books.first { $0.id == preferred }
                    ?? books.first { $0.isDefault == true }
                    ?? books[0]

                async let accountsTask = client.accounts(bookID: book.id)
                async let categoriesTask = client.categories(bookID: book.id)
                async let assetsTask = client.assets(bookID: book.id)
                async let transactionsTask = client.transactions(bookID: book.id, pageSize: 20)

                let accountsValue = try await accountsTask
                let categoriesValue = try await categoriesTask
                let assetsValue = try await assetsTask
                let transactionsValue = try await transactionsTask
                let cards = (try? await client.creditSummary()) ?? []

                return HuozhiSnapshot(
                    user: user,
                    books: books,
                    selectedBookID: book.id,
                    accounts: accountsValue.accounts,
                    accountSummary: accountsValue.summary,
                    categories: categoriesValue,
                    assets: assetsValue,
                    creditCards: cards,
                    transactions: transactionsValue
                )
            }
            snapshot = value
            selectedBookID = value.selectedBookID
            lastUpdated = .now
            center.markValid(serviceID: "huozhi")
            await center.cache.save(value, serviceID: "huozhi")
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "huozhi")
        }
        isLoading = false
    }

    func selectBook(_ id: Int) {
        selectedBookID = id
        Task { await refresh() }
    }

    // MARK: - 写入

    func submit(_ draft: HuozhiDraft, currency: String?) async -> SubmitOutcome {
        let validated: HuozhiDraft
        do {
            validated = try draft.validated()
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        guard !isSubmitting else { return .failed("正在提交，请稍候") }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let created = try await withAuth { jwt in
                try await client(jwt: jwt).create(validated, currency: currency)
            }
            await refresh()
            return .saved(created)
        } catch {
            let apiError = error as? IntegrationAPIError ?? .transport(error.localizedDescription)
            if isAmbiguous(apiError) {
                if await reconcile(validated) {
                    return .saved(HuozhiTransaction(
                        id: 0,
                        type: validated.kind.isTransfer ? "transfer" : validated.kind.rawValue,
                        amount: NSDecimalNumber(decimal: validated.amount).doubleValue,
                        txDate: validated.date,
                        description: validated.note
                    ))
                }
                return .unknown
            }
            if apiError.needsReauthorization {
                center.reportError(apiError, for: "huozhi")
            }
            self.error = apiError.userMessage
            return .failed(apiError.userMessage)
        }
    }

    /// 超时/5xx 时服务端可能已经写入；拉最近流水核对，找到就当成功，找不到就交给用户决定。
    func reconcile(_ draft: HuozhiDraft) async -> Bool {
        do {
            let page = try await withAuth { jwt in
                try await client(jwt: jwt).transactions(bookID: draft.bookID, pageSize: 50)
            }
            let candidates = page.grouped.flatMap(\.transactions).map { transaction in
                HuozhiReconcileCandidate(
                    id: transaction.id,
                    amount: HuozhiDate.decimal(from: transaction.amount),
                    accountID: transaction.accountId ?? 0,
                    toAccountID: transaction.toAccountId,
                    day: transaction.day,
                    note: [transaction.description, transaction.remark]
                        .compactMap { $0 }
                        .joined(separator: " ")
                )
            }
            guard candidates.contains(where: { draft.matches($0) }) else {
                return false
            }
            await refresh()
            return true
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            return false
        }
    }

    private func withAuth<T>(_ operation: (String) async throws -> T) async throws -> T {
        guard let jwt = center.credential(for: "huozhi")?.jwt, !jwt.isEmpty else {
            throw IntegrationAPIError.unauthorized
        }
        do {
            return try await operation(jwt)
        } catch let error as IntegrationAPIError where error.needsReauthorization {
            await center.validateIfConfigured(serviceID: "huozhi", baseURL: baseURL)
            guard let refreshed = center.credential(for: "huozhi")?.jwt,
                  !refreshed.isEmpty,
                  refreshed != jwt else {
                throw error
            }
            return try await operation(refreshed)
        }
    }

    private func isAmbiguous(_ error: IntegrationAPIError) -> Bool {
        switch error {
        case .transport, .decoding:
            true
        case .http(let status, _):
            status >= 500
        default:
            false
        }
    }

    // MARK: - 派生数据

    var books: [HuozhiBook] { snapshot?.books ?? [] }

    var accounts: [HuozhiAccount] {
        (snapshot?.accounts ?? []).filter { $0.isArchived != true && $0.isHidden != true }
    }

    var creditAccounts: [HuozhiAccount] {
        accounts.filter(\.isCredit)
    }

    var paymentAccounts: [HuozhiAccount] {
        accounts.filter { !$0.isCredit }
    }

    var expenseOptions: [HuozhiCategoryOption] {
        options(kind: "expense")
    }

    var incomeOptions: [HuozhiCategoryOption] {
        options(kind: "income")
    }

    var recentGroups: [HuozhiDayGroup] {
        snapshot?.transactions.grouped ?? []
    }

    var creditCards: [HuozhiCreditCard] {
        if let cards = snapshot?.creditCards, !cards.isEmpty { return cards }
        return creditAccounts.map { account in
            HuozhiCreditCard(
                id: account.id,
                name: account.name,
                bankName: account.bankName,
                cardNo4: account.cardNo4,
                repayDay: account.repayDay,
                billDay: account.billDay,
                balance: account.balance,
                creditLimit: account.creditLimit
            )
        }
    }

    func account(id: Int?) -> HuozhiAccount? {
        guard let id else { return nil }
        return accounts.first { $0.id == id }
    }

    func accountName(id: Int?) -> String? {
        guard let id else { return nil }
        return snapshot?.accounts.first { $0.id == id }?.name
    }

    func currency(for accountID: Int?) -> String? {
        account(id: accountID)?.currency
    }

    private func options(kind: String) -> [HuozhiCategoryOption] {
        guard let tree = snapshot?.categories else { return [] }
        return tree.flattened(kind: kind)
            .filter { $0.category.isHidden != true }
            .map { item in
                HuozhiCategoryOption(
                    id: item.category.id,
                    title: String(repeating: "　", count: item.depth) + item.category.name,
                    depth: item.depth
                )
            }
    }
}
