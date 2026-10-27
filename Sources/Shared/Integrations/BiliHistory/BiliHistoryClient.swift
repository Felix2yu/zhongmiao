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
        try await records(size: limit)
    }

    /// 历史列表。带主分类时按分类筛选（搜索接口不支持这个参数）。
    func records(mainCategory: String? = nil, size: Int = 30) async throws -> [BiliHistoryRecord] {
        var items = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "sort_order", value: "0")
        ]
        if let mainCategory, !mainCategory.isEmpty {
            items.append(URLQueryItem(name: "main_category", value: mainCategory))
        }
        let data = try await http.data("/history/all", query: items)
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

    /// 搜索观看历史。search_type 支持 all / title / author。
    func search(
        query: String,
        page: Int = 1,
        size: Int = 30,
        searchType: String = "all"
    ) async throws -> BiliHistoryPageData {
        let data = try await http.data(
            "/history/search",
            query: [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "search_type", value: searchType),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size)),
                URLQueryItem(name: "sortOrder", value: "0")
            ]
        )
        let payload = try unwrapStatus(data)
        return try decode(payload, path: "/history/search")
    }

    /// 主分类，用于筛选。
    func mainCategories() async throws -> [BiliMainCategory] {
        let data = try await http.data("/categories/main-categories")
        let payload = try unwrapStatus(data)
        return try decode(payload, path: "/categories/main-categories")
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
