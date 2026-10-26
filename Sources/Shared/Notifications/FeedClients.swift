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

    /// 执行请求并把 HTTP 状态码原样带回（不因 4xx/5xx 抛错）。
    ///
    /// 标记已读需要区分「服务端拒绝写入（401/403）」和「目标已不存在（404）」，
    /// 所以不能走上面的 `data(_:)` —— 它会把所有非 2xx 都变成异常。
    private func rawResponse(
        _ url: URL,
        headers: [String: String] = [:],
        method: String = "GET",
        timeout: TimeInterval = 15
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
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
    func fetchNtfyTopics(base: URL, token: String? = nil) async throws -> [String] {
        struct TopicPage: Decodable {
            var topics: [String]
        }
        let payload = try await withRetry(attempts: 2) {
            try await data(base.appendingPathComponent("v1/topics"), headers: ntfyAuthHeaders(token: token))
        }
        let page = try JSONDecoder().decode(TopicPage.self, from: payload)
        var seen = Set<String>()
        return page.topics.compactMap { NtfyTopic.normalized($0) }
            .filter { seen.insert($0).inserted }
    }

    // MARK: - ntfy

    /// 一次 ntfy 轮询的结果。
    struct NtfyPollResult: Sendable {
        /// 可投递的真实消息。
        var items: [NotificationItem] = []
        /// 服务端广播的「已读」目标（消息 id 或序列 id）。
        var clearedTargets: [String] = []
        /// 本批消息（含动作事件）的最新时间，用来推进游标。
        var newestAt: Date?
    }

    /// 标记已读请求的结果。
    enum NtfyReadOutcome: Sendable, Equatable {
        /// 服务端已接受。
        case accepted
        /// 目标已不在服务端（404）：想达到的状态已经成立。
        case notFound
        /// 服务端拒绝写入（401/403）：缺令牌或没有该主题的写权限，重试没有意义。
        case rejected(status: Int)
        /// 网络错误、429、5xx：可以稍后重试。
        case failed
    }

    /// 拉一轮 ntfy 主题。
    ///
    /// 除了普通消息，流里还可能夹着服务端广播的动作事件：`message_clear` 表示
    /// 「别处把这条消息标记为已读」，`message_delete` 表示消息已被删除。
    func fetchNtfy(
        base: URL,
        topic: String,
        serviceID: String,
        since: Date,
        token: String? = nil
    ) async throws -> NtfyPollResult {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else { return NtfyPollResult() }

        var components = URLComponents(
            url: base.appendingPathComponent(trimmedTopic).appendingPathComponent("json"),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = [
            URLQueryItem(name: "poll", value: "1"),
            URLQueryItem(name: "since", value: NtfyStreamDecoder.sinceParameter(since))
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let payload = try await withRetry {
            try await data(url, headers: ntfyAuthHeaders(token: token))
        }
        guard !payload.isEmpty else { return NtfyPollResult() }
        var buffer = String(decoding: payload, as: UTF8.self)
        if !buffer.hasSuffix("\n") { buffer += "\n" }
        let messages = NtfyStreamDecoder.drain(buffer: &buffer)

        var result = NtfyPollResult()
        var newest: Date?
        var cleared = Set<String>()
        for message in messages {
            if let time = message.time {
                let date = Date(timeIntervalSince1970: TimeInterval(time))
                if newest == nil || date > newest! { newest = date }
            }
            // 已读事件不投递成通知，只用来把本地条目标成已读。
            if message.isClearEvent, let target = message.actionTargetID {
                cleared.insert(target)
                continue
            }
            if let item = message.notificationItem(serviceID: serviceID, fallbackURL: base) {
                result.items.append(item)
            }
        }
        result.clearedTargets = Array(cleared)
        result.newestAt = newest
        return result
    }

    /// 告诉服务端「这些消息已读」：`GET {base}/{topic}/{id1,id2,…}/read`。
    ///
    /// 服务端把它变成一条 `message_clear` 广播，网页版与其它设备都会跟着把消息标成已读；
    /// 众妙自己下一轮轮询也会收到这条回声（幂等，不会重复计数）。
    ///
    /// 本地已读状态已经落库，这里只是尽力而为：失败不影响本地，只会让服务端落后。
    func markNtfyRead(
        base: URL,
        topic: String,
        ids: [String],
        token: String? = nil
    ) async -> NtfyReadOutcome {
        let chunks = NtfyActionID.chunks(ids)
        guard !chunks.isEmpty else { return .accepted }
        for chunk in chunks {
            let outcome = await markNtfyReadChunk(base: base, topic: topic, ids: chunk, token: token)
            switch outcome {
            case .accepted, .notFound:
                continue
            case .rejected:
                return outcome
            case .failed:
                // 上游 ntfy 的路由只认单个 id，批量形态会 404；这时降级逐个标记。
                if chunk.count > 1 {
                    return await markNtfyReadOneByOne(base: base, topic: topic, ids: chunk, token: token)
                }
                return outcome
            }
        }
        return .accepted
    }

    /// 逐个标记已读（上游 ntfy 只认单个 id 的路由）。
    private func markNtfyReadOneByOne(
        base: URL,
        topic: String,
        ids: [String],
        token: String?
    ) async -> NtfyReadOutcome {
        var worst: NtfyReadOutcome = .accepted
        for id in ids {
            let outcome = await markNtfyReadChunk(base: base, topic: topic, ids: [id], token: token)
            switch outcome {
            case .accepted, .notFound:
                continue
            case .rejected:
                return outcome
            case .failed:
                worst = .failed
            }
        }
        return worst
    }

    /// `GET {base}/{topic}/{ids}/read`。
    private func markNtfyReadChunk(
        base: URL,
        topic: String,
        ids: [String],
        token: String?
    ) async -> NtfyReadOutcome {
        guard let url = actionURL(base: base, topic: topic, ids: ids, suffix: "read") else {
            return .failed
        }
        do {
            let (_, response) = try await rawResponse(url, headers: ntfyAuthHeaders(token: token))
            switch response.statusCode {
            case 200..<300:
                return .accepted
            case 404:
                // 主题或消息已经不在服务端：想达到的状态已经成立。
                return .notFound
            case 401, 403:
                return .rejected(status: response.statusCode)
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    /// 拼出 `/{topic}/{ids}/{suffix}` 形式的路径，保留 base 里的路径前缀。
    ///
    /// 不能用 `appendingPathComponent` —— 它会把 id 之间的逗号和分隔符一起编码掉。
    private func actionURL(base: URL, topic: String, ids: [String], suffix: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = "\(basePath)/\(topic)/\(ids.joined(separator: ","))/\(suffix)"
        return components.url
    }

    /// ntfy 的鉴权头。服务端开了访问控制时，读和写都要带令牌。
    private func ntfyAuthHeaders(token: String?) -> [String: String] {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? [:] : ["Authorization": "Bearer \(trimmed)"]
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
