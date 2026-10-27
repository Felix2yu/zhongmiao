import Foundation
import ZhongmiaoCore

struct DiarumClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, jwt: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api/v1", token: jwt)
    }

    func diary(date: String) async throws -> DiarumDiary? {
        let data = try await http.data("/diaries/by-date/\(date)")
        do {
            let diary = try JSONDecoder().decode(DiarumDiary.self, from: data)
            return diary.exists == false ? nil : diary
        } catch {
            throw IntegrationAPIError.decoding("吾身当日日记：\(error.localizedDescription)")
        }
    }

    /// 按日期写入正文。服务端是 upsert，且 **未显式传入的情绪/场景/标签保持原值**，
    /// 所以只带 date + content 不会清掉这些字段。
    func save(date: String, content: String) async throws -> DiarumDiary {
        let body = try JSONEncoder().encode(["date": date, "content": content])
        let data = try await http.data("/diaries", method: "POST", body: body)
        do {
            return try JSONDecoder().decode(DiarumDiary.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("吾身保存日记：\(error.localizedDescription)")
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

    func search(_ query: String) async throws -> [DiarumSearchHit] {
        let data = try await http.data(
            "/diaries/search",
            query: [URLQueryItem(name: "q", value: query)]
        )
        do {
            return try JSONDecoder().decode(DiarumSearchResponse.self, from: data).results
        } catch {
            throw IntegrationAPIError.decoding("吾身搜索：\(error.localizedDescription)")
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
