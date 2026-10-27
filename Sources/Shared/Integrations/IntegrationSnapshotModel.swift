import Foundation
import Observation
import ZhongmiaoCore

/// 只读原生页的通用状态：缓存 → 网络 → 写回缓存。
/// 有写操作的应用各自实现轻量 Model，不强行套这一层。
@MainActor
@Observable
final class IntegrationSnapshotModel<Payload: Codable & Sendable> {

    let serviceID: String
    let baseURL: URL
    let center: IntegrationCenter

    private(set) var snapshot: Payload?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?

    private let loader: @MainActor () async throws -> Payload

    init(
        serviceID: String,
        baseURL: URL,
        center: IntegrationCenter,
        loader: @escaping @MainActor () async throws -> Payload
    ) {
        self.serviceID = serviceID
        self.baseURL = baseURL
        self.center = center
        self.loader = loader
    }

    func loadCache() async {
        guard snapshot == nil else { return }
        if let cached = await center.cache.load(Payload.self, serviceID: serviceID) {
            snapshot = cached.payload
            lastUpdated = cached.fetchedAt
        }
    }

    func refreshIfNeeded(maxAge: TimeInterval = 300) async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            let value = try await loader()
            snapshot = value
            lastUpdated = .now
            center.markValid(serviceID: serviceID)
            await center.cache.save(value, serviceID: serviceID, protect: serviceID == "yuexi")
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: serviceID)
        }
        isLoading = false
    }
}
