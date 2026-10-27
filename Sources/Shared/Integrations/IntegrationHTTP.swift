import Foundation
import ZhongmiaoCore

/// 原生接入的 HTTP 层。只负责拼地址、带凭据、判状态、转错误；
/// 各应用的信封与 DTO 仍由各自 Client 处理。
struct IntegrationHTTP: Sendable {

    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Zhongmiao/0.1"]
        return URLSession(configuration: configuration)
    }()

    let baseURL: URL
    let basePath: String
    let token: String?
    let cookie: String?
    let session: URLSession

    init(
        baseURL: URL,
        basePath: String,
        token: String? = nil,
        cookie: String? = nil,
        session: URLSession = IntegrationHTTP.defaultSession
    ) {
        self.baseURL = baseURL
        self.basePath = basePath
        self.token = token
        self.cookie = cookie
        self.session = session
    }

    func raw(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = makeURL(path: path, query: query) else {
            throw IntegrationAPIError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
            }
        }
        if let cookie, !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body {
            request.httpBody = body
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw IntegrationAPIError.transport("服务没有返回 HTTP 响应")
            }
            return (data, http)
        } catch let error as IntegrationAPIError {
            throw error
        } catch let error as URLError {
            throw IntegrationAPIError.transport(error.localizedDescription)
        } catch {
            throw IntegrationAPIError.transport(error.localizedDescription)
        }
    }

    func data(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws -> Data {
        let (data, response) = try await raw(
            path,
            query: query,
            method: method,
            body: body,
            contentType: contentType,
            headers: headers,
            timeout: timeout
        )
        try validate(response: response, data: data)
        return data
    }

    func decoded<T: Decodable>(
        _ type: T.Type,
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        decoder: JSONDecoder = JSONDecoder(),
        timeout: TimeInterval = 15
    ) async throws -> T {
        let data = try await data(
            path,
            query: query,
            method: method,
            body: body,
            contentType: contentType,
            headers: headers,
            timeout: timeout
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("\(path)：\(error.localizedDescription)")
        }
    }

    func send(
        _ path: String,
        query: [URLQueryItem] = [],
        method: String = "POST",
        body: Data? = nil,
        contentType: String? = nil,
        headers: [String: String] = [:],
        timeout: TimeInterval = 15
    ) async throws {
        _ = try await data(
            path,
            query: query,
            method: method,
            body: body,
            contentType: contentType,
            headers: headers,
            timeout: timeout
        )
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        let status = response.statusCode
        switch status {
        case 401:
            throw IntegrationAPIError.unauthorized
        case 403:
            throw IntegrationAPIError.forbidden
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw IntegrationAPIError.rateLimited(retryAfter: retryAfter)
        case 300..<400:
            throw IntegrationAPIError.unauthorized
        case 200..<300:
            break
        default:
            throw IntegrationAPIError.http(status: status, message: IntegrationEnvelope.message(from: data))
        }

        if let mime = response.mimeType?.lowercased(), mime.contains("text/html") {
            throw IntegrationAPIError.notJSON
        }
        guard !data.isEmpty else { return }
        if !IntegrationEnvelope.isLikelyJSON(data) {
            let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
            if data.first(where: { !whitespace.contains($0) }) == UInt8(ascii: "<") {
                throw IntegrationAPIError.notJSON
            }
        }
    }

    private func makeURL(path: String, query: [URLQueryItem]) -> URL? {
        let components = [basePath, path]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        var url = baseURL
        for part in components.split(separator: "/") {
            url.appendPathComponent(String(part))
        }
        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !query.isEmpty {
            urlComponents.queryItems = query
        }
        return urlComponents.url
    }
}
