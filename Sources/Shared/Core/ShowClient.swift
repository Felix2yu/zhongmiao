import Foundation
import ZhongmiaoCore

/// 幕间「未来演出」接口的客户端。
///
/// 只做一件事：把 `GET /api/records/upcoming?days=N` 拉回来、转成 `Show`。
/// 地址与令牌由调用方解析后传入，本类型不读设置——这样它能在 Intent 里被复用
/// （Intent 只读缓存不联网，但保持依赖清晰没有坏处）。
struct ShowClient: Sendable {

    struct Failure: Error, Sendable, CustomStringConvertible {
        let status: Int
        var description: String { "幕间返回 HTTP \(status)" }
    }

    /// 拉取未来多少天的演出。与幕间接口的上限（90 天）对齐不了时会被服务端夹住，无需在此校验。
    var days = 14

    var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Zhongmiao/0.1 (iOS)"]
        return URLSession(configuration: configuration)
    }()

    /// 拉取未来演出。
    ///
    /// - Parameters:
    ///   - baseURL: 幕间站点根地址，来自 `ServiceURLResolver`（域名、子路径、内网端口三种模式都支持）。
    ///   - token: `MJ_AUTH_TOKEN`。幕间免鉴权时留空，此时不发送 Authorization 头。
    func fetchUpcoming(baseURL: URL, token: String = "") async throws -> [Show] {
        var components = URLComponents(
            url: baseURL.appending(path: "api/records/upcoming"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "days", value: String(days))]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure(status: http.statusCode)
        }

        // 整份解码失败就抛：宁可留下旧缓存，也不要用半截数据覆盖它。
        let decoded = try JSONDecoder().decode(MujianUpcomingResponse.self, from: data)
        return decoded.items.compactMap { $0.makeShow(baseURL: baseURL) }
    }
}
