import Foundation
import ZhongmiaoCore

struct LiuxiaClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api")
    }

    func today() async throws -> LiuxiaToday {
        let data = try await http.data("/today")
        do {
            return try JSONDecoder().decode(LiuxiaToday.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("流霞今日预报：\(error.localizedDescription)")
        }
    }

    func cities() async throws -> [String] {
        let data = try await http.data("/cities")
        do {
            return try JSONDecoder().decode([String].self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("流霞城市：\(error.localizedDescription)")
        }
    }

    func rankings() async throws -> LiuxiaRankings {
        let data = try await http.data("/rankings")
        do {
            return try JSONDecoder().decode(LiuxiaRankings.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("流霞排行：\(error.localizedDescription)")
        }
    }
}
