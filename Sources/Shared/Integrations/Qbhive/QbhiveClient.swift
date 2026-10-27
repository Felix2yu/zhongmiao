import Foundation
import ZhongmiaoCore

struct QbhiveClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, token: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: token)
    }

    func stats() async throws -> QbhiveStats {
        let data = try await http.data("/torrents/stats")
        return try decode(unwrapIfNeeded(data), path: "/torrents/stats")
    }

    func torrents() async throws -> [QbhiveTorrent] {
        let data = try await http.data(
            "/torrents",
            query: [
                URLQueryItem(name: "filter", value: "all"),
                URLQueryItem(name: "limit", value: "50")
            ]
        )
        let payload = try unwrapIfNeeded(data)
        if let list = try? JSONDecoder().decode([QbhiveTorrent].self, from: payload) {
            return list
        }
        if let object = try? JSONDecoder().decode([String: [QbhiveTorrent]].self, from: payload) {
            return object["data"] ?? object["torrents"] ?? object.values.first ?? []
        }
        throw IntegrationAPIError.decoding("蜂巢种子列表")
    }

    func feeds() async throws -> [QbhiveFeed] {
        let data = try await http.data("/rss/status")
        let payload = try unwrapIfNeeded(data)
        if let list = try? JSONDecoder().decode([QbhiveFeed].self, from: payload) {
            return list
        }
        if let object = try? JSONDecoder().decode([String: [QbhiveFeed]].self, from: payload) {
            return object["data"] ?? object.values.first ?? []
        }
        if payload == Data("null".utf8) { return [] }
        throw IntegrationAPIError.decoding("蜂巢 RSS 状态")
    }

    func perform(_ action: String, hash: String) async throws {
        let body = try JSONEncoder().encode(ActionBody(action: action))
        try await http.send("/torrents/\(hash)/action", method: "POST", body: body)
    }

    private struct ActionBody: Encodable {
        let action: String
    }

    private func unwrapIfNeeded(_ data: Data) throws -> Data {
        guard let object = IntegrationEnvelope.object(from: data) else {
            throw IntegrationAPIError.notJSON
        }
        if object["success"] != nil || object["code"] != nil {
            return try IntegrationEnvelope.unwrapCode(data)
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data, path: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("蜂巢 \(path)：\(error.localizedDescription)")
        }
    }
}
