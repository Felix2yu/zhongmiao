import Foundation
import ZhongmiaoCore

/// 从各个自建服务拉取通知的 HTTP 客户端集合。
///
/// 三条通道互补：
/// - **feed**：应用自己实现的 `GET /api/notifications?since=…`（首选，语义最准）。
/// - **ntfy**：自托管 ntfy 的 `/{topic}/json?poll=1&since=…`，零改造即可接告警类事件。
/// - **relay**：自建推送中继的历史事件接口，用于 APNs 已推过但 App 没收到时的补发。
struct FeedClients: Sendable {

    struct HTTPFailure: Error, Sendable, CustomStringConvertible {
        let status: Int
        let url: URL
        var description: String { "HTTP \(status)" }
    }

    var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Zhongmiao/0.1 (iOS)"]
        return URLSession(configuration: configuration)
    }()

    var retryPolicy = RetryPolicy(base: 1.5, maximum: 20, multiplier: 2, jitter: 0.25)

    // MARK: - 底层请求

    private func data(
        _ url: URL,
        headers: [String: String] = [:],
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = 15
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw HTTPFailure(status: http.statusCode, url: url)
        }
        return data
    }

    /// 有限次重试；失败后交给下一次同步，不阻塞其它服务。
    func withRetry<T: Sendable>(
        attempts: Int = 3,
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: (any Error)?
        for attempt in 1...max(1, attempts) {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < attempts {
                    let delay = retryPolicy.delay(forAttempt: attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    // MARK: - ntfy 主题目录

    /// 服务器上有缓存消息的主题。`GET /v1/topics` 不要求鉴权，返回 `{"topics":["a","b"]}`。
    ///
    /// 这是「浏览服务器主题、一键订阅」的数据源：不依赖 ntfy 网页版，内嵌页面里
    /// 顶部菜单被遮挡时也能正常加主题。
    func fetchNtfyTopics(base: URL) async throws -> [String] {
        struct TopicPage: Decodable {
            var topics: [String]
        }
        let payload = try await withRetry(attempts: 2) {
            try await data(base.appendingPathComponent("v1/topics"))
        }
        let page = try JSONDecoder().decode(TopicPage.self, from: payload)
        var seen = Set<String>()
        return page.topics.compactMap { NtfyTopic.normalized($0) }
            .filter { seen.insert($0).inserted }
    }

    // MARK: - ntfy

    func fetchNtfy(
        base: URL,
        topic: String,
        serviceID: String,
        since: Date
    ) async throws -> [NotificationItem] {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else { return [] }

        var components = URLComponents(
            url: base.appendingPathComponent(trimmedTopic).appendingPathComponent("json"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "poll", value: "1"),
            URLQueryItem(name: "since", value: NtfyStreamDecoder.sinceParameter(since))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let payload = try await withRetry { try await data(url) }
        guard !payload.isEmpty else { return [] }
        var buffer = String(decoding: payload, as: UTF8.self)
        if !buffer.hasSuffix("\n") { buffer += "\n" }
        return NtfyStreamDecoder.drain(buffer: &buffer)
            .compactMap { $0.notificationItem(serviceID: serviceID, fallbackURL: base) }
    }

    // MARK: - 通用 feed

    func fetchFeed(
        base: URL,
        path: String,
        serviceID: String,
        since: Date,
        limit: Int = 50
    ) async throws -> [NotificationItem] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let endpoint: URL? = {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return URL(string: trimmed)
            }
            return URL(string: trimmed.hasPrefix("/") ? trimmed : "/" + trimmed, relativeTo: base)?.absoluteURL
        }()
        guard let endpoint, var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "since", value: FlexibleDate.iso8601.string(from: since)))
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }

        let payload = try await withRetry { try await data(url) }
        let page = try FeedParser.decode(payload)
        return FeedParser.items(from: page, serviceID: serviceID, baseURL: base)
    }

    // MARK: - 推送中继

    func fetchRelayEvents(
        relay: URL,
        secret: String,
        serviceID: String,
        since: Date
    ) async throws -> [NotificationItem] {
        var components = URLComponents(url: relay.appendingPathComponent("v1/events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "service", value: serviceID),
            URLQueryItem(name: "since", value: FlexibleDate.iso8601.string(from: since))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let authHeaders: [String: String] = secret.isEmpty ? [:] : ["X-Zhongmiao-Token": secret]

        let payload = try await withRetry { try await data(url, headers: authHeaders) }
        let page = try FeedParser.decode(payload)
        return FeedParser.items(from: page, serviceID: serviceID, baseURL: nil)
    }

    /// 注册 APNs 设备令牌。
    func registerDevice(
        relay: URL,
        secret: String,
        token: String,
        platform: String,
        deviceName: String
    ) async throws {
        let body: [String: String] = [
            "token": token,
            "platform": platform,
            "deviceName": deviceName,
            "bundle": Bundle.main.bundleIdentifier ?? "im.yufei.zhongmiao"
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let authHeaders: [String: String] = secret.isEmpty ? [:] : ["X-Zhongmiao-Token": secret]
        _ = try await withRetry(attempts: 2) {
            try await data(relay.appendingPathComponent("v1/devices"), headers: authHeaders, method: "POST", body: payload)
        }
    }

    // MARK: - 体检

    func probe(_ url: URL) async -> ServiceHealth {
        let start = CFAbsoluteTimeGetCurrent()
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(reason: "非 HTTP 响应")
            }
            return HealthClassifier.merging(
                HealthClassifier.classify(statusCode: http.statusCode),
                latencyMilliseconds: latency
            )
        } catch let error as URLError {
            return HealthClassifier.classify(errorCode: error.errorCode, description: error.localizedDescription)
        } catch {
            return .unreachable(reason: error.localizedDescription)
        }
    }
}
