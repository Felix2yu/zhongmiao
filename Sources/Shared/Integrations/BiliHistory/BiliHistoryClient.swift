import Foundation
import ZhongmiaoCore

struct BiliHistoryClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api")
    }

    func dailyCount() async throws -> BiliDailyCount {
        let now = Date()
        let calendar = Calendar.current
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let md = String(format: "%02d%02d", month, day)
        let data = try await http.data(
            "/daily/daily-count",
            query: [
                URLQueryItem(name: "date", value: md),
                URLQueryItem(name: "year", value: String(calendar.component(.year, from: now)))
            ]
        )
        let payload = try unwrapStatus(data)
        return try decode(payload, path: "/daily/daily-count")
    }

    func recentRecords(limit: Int = 30) async throws -> [BiliHistoryRecord] {
        let data = try await http.data(
            "/history/all",
            query: [
                URLQueryItem(name: "page", value: "1"),
                URLQueryItem(name: "size", value: String(limit)),
                URLQueryItem(name: "sort_order", value: "0")
            ]
        )
        let payload = try unwrapStatus(data)
        let page: BiliHistoryPageData = try decode(payload, path: "/history/all")
        return page.records
    }

    func monthlyStats() async throws -> BiliMonthlyStats {
        let year = Calendar.current.component(.year, from: .now)
        let data = try await http.data(
            "/viewing/monthly-stats",
            query: [URLQueryItem(name: "year", value: String(year))]
        )
        let payload = try unwrapStatus(data)
        return try decode(payload, path: "/viewing/monthly-stats")
    }

    private func unwrapStatus(_ data: Data) throws -> Data {
        try IntegrationEnvelope.unwrapStatus(data)
    }

    private func decode<T: Decodable>(_ data: Data, path: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("拾帧集 \(path)：\(error.localizedDescription)")
        }
    }
}
