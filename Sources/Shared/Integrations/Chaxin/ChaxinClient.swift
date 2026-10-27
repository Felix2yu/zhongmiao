import Foundation
import ZhongmiaoCore

struct ChaxinClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api")
    }

    func repos() async throws -> [ChaxinRepo] {
        let data = try await http.data("/repos")
        do {
            return try JSONDecoder().decode([ChaxinRepo].self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("察新仓库：\(error.localizedDescription)")
        }
    }

    func notifications(limit: Int = 20) async throws -> [ChaxinNotification] {
        let data = try await http.data(
            "/notifications",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        do {
            return try JSONDecoder().decode([ChaxinNotification].self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("察新通知：\(error.localizedDescription)")
        }
    }
}
