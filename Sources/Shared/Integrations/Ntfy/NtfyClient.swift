import Foundation
import ZhongmiaoCore

struct NtfyMessagesResponse: Decodable {
    var messages: [NtfyMessage]
}

struct NtfyTopicsResponse: Decodable {
    var topics: [String]
}

struct NtfyClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, token: String?) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "", token: token)
    }

    func topics() async throws -> [String] {
        let data = try await http.data("/v1/topics")
        do {
            return try JSONDecoder().decode(NtfyTopicsResponse.self, from: data).topics
        } catch {
            throw IntegrationAPIError.decoding("ntfy 主题：\(error.localizedDescription)")
        }
    }

    func messages(topic: String) async throws -> [NtfyMessage] {
        let data = try await http.data(
            "/\(topic)/json",
            query: [
                URLQueryItem(name: "poll", value: "1"),
                URLQueryItem(name: "since", value: "7d")
            ]
        )
        guard var buffer = String(data: data, encoding: .utf8) else { return [] }
        var messages = NtfyStreamDecoder.drain(buffer: &buffer)
        if let last = NtfyStreamDecoder.decode(line: buffer) {
            messages.append(last)
        }
        return messages.filter(\.isDeliverable)
    }

    func search(query: String) async throws -> [NtfyMessage] {
        let data = try await http.data(
            "/v1/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "50")
            ]
        )
        do {
            return try JSONDecoder().decode(NtfyMessagesResponse.self, from: data).messages.filter(\.isDeliverable)
        } catch {
            throw IntegrationAPIError.decoding("ntfy 搜索：\(error.localizedDescription)")
        }
    }

    func markRead(topic: String, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let joined = ids.prefix(50).joined(separator: ",")
        try await http.send("/\(topic)/\(joined)/read", method: "GET")
    }

    func delete(topic: String, id: String) async throws {
        try await http.send("/\(topic)/\(id)", method: "DELETE")
    }
}
