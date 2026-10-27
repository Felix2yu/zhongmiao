import Foundation
import ZhongmiaoCore

struct LiuxiaClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api")
    }

    func today(city: String? = nil) async throws -> LiuxiaToday {
        var query: [URLQueryItem] = []
        if let city, !city.isEmpty {
            query.append(URLQueryItem(name: "city", value: city))
        }
        let data = try await http.data("/today", query: query)
        do {
            return try JSONDecoder().decode(LiuxiaToday.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("流霞今明预报：\(error.localizedDescription)")
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

    /// 区间内质量最高的场次。用来找「即将到来的优质朝霞晚霞」。
    func rankings(
        city: String? = nil,
        eventType: LiuxiaEvent.Kind? = nil,
        start: String,
        end: String
    ) async throws -> LiuxiaRankings {
        var query = [
            URLQueryItem(name: "start", value: start),
            URLQueryItem(name: "end", value: end)
        ]
        if let city, !city.isEmpty {
            query.append(URLQueryItem(name: "city", value: city))
        }
        if let eventType {
            query.append(URLQueryItem(name: "event_type", value: eventType.rawValue))
        }
        let data = try await http.data("/rankings", query: query)
        do {
            return try JSONDecoder().decode(LiuxiaRankings.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("流霞排行：\(error.localizedDescription)")
        }
    }
}
