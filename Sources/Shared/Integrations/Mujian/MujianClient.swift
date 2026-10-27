import Foundation
import ZhongmiaoCore

struct MujianClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, token: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: token)
    }

    func dashboard() async throws -> MujianDashboard {
        let data = try await http.data("/dashboard")
        do {
            return try JSONDecoder().decode(MujianDashboard.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("幕间看板：\(error.localizedDescription)")
        }
    }
}
