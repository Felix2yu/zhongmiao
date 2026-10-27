import Foundation
import ZhongmiaoCore

struct DiarumClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, jwt: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api/v1", token: jwt)
    }

    func today(date: String) async throws -> DiarumDiary? {
        let data = try await http.data("/diaries/by-date/\(date)")
        do {
            let diary = try JSONDecoder().decode(DiarumDiary.self, from: data)
            return diary.exists == false ? nil : diary
        } catch {
            throw IntegrationAPIError.decoding("吾身今日日记：\(error.localizedDescription)")
        }
    }

    func recent(limit: Int = 5) async throws -> [DiarumDiary] {
        let data = try await http.data(
            "/diaries/recent",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
        do {
            return try JSONDecoder().decode(DiarumRecentResponse.self, from: data).diaries
        } catch {
            throw IntegrationAPIError.decoding("吾身最近日记：\(error.localizedDescription)")
        }
    }

    func stats() async throws -> DiarumStats {
        let data = try await http.data(
            "/diaries/stats",
            query: [URLQueryItem(name: "tz", value: TimeZone.current.identifier)]
        )
        do {
            return try JSONDecoder().decode(DiarumStats.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("吾身统计：\(error.localizedDescription)")
        }
    }
}
