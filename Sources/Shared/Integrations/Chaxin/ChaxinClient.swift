import Foundation
import ZhongmiaoCore

struct ChaxinClient: Sendable {

    private let http: IntegrationHTTP

    /// 加仓库要联机问一次 GitHub，立即检查后端最多跑 3 分钟——都用长超时的会话，
    /// 默认会话的资源上限只有 30 秒会被截断。
    private static let longSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 200
        configuration.timeoutIntervalForResource = 210
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Zhongmiao/0.1"]
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL) {
        self.http = IntegrationHTTP(
            baseURL: baseURL,
            basePath: "/api",
            session: Self.longSession
        )
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

    /// 添加一个要监控的仓库。后端会联机向 GitHub 查一次，格式必须是 owner/repo。
    func addRepo(fullName: String) async throws -> ChaxinAddedRepo {
        let body = try JSONEncoder().encode(["full_name": fullName])
        let data = try await http.data("/repos", method: "POST", body: body, timeout: 60)
        do {
            return try JSONDecoder().decode(ChaxinAddedRepo.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("察新添加仓库：\(error.localizedDescription)")
        }
    }

    /// 立刻跑一轮检查。后端最多跑 3 分钟。
    func runMonitor() async throws {
        try await http.send("/monitor/run", method: "POST", timeout: 200)
    }

    /// 重发一条发送失败的通知。
    func retryNotification(id: Int64) async throws {
        try await http.send("/notifications/\(id)/retry", method: "POST", timeout: 60)
    }
}
