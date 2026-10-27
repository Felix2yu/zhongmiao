import Foundation
import ZhongmiaoCore

struct MujianClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, token: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: token)
    }

    func dashboard() async throws -> MujianDashboard {
        try await decode("/dashboard", label: "幕间看板")
    }

    /// 演出列表。`query` 走服务端过滤，分页用 limit/offset。
    func records(query: String = "", limit: Int = 30, offset: Int = 0) async throws -> MujianRecordList {
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        return try await decode("/records", query: items, label: "幕间演出列表")
    }

    func record(id: String) async throws -> MujianRecord {
        try await decode("/records/\(id)", label: "幕间演出详情")
    }

    /// 只改「已观看」。
    ///
    /// 服务端的 `PUT /records/{id}` 虽然注释写着「部分更新」，实际只对 `date` 生效：
    /// 没带的字段会被写成零值（实测只发 `{"watched":true}` 会把剧目名、座位、分类全清空）。
    /// 所以这里先取原始 JSON，只改 `watched` 再整份回写，未识别的字段也一并保留。
    func setWatched(id: String, watched: Bool) async throws -> MujianRecord {
        let raw = try await http.data("/records/\(id)")
        guard var object = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            throw IntegrationAPIError.decoding("幕间演出详情不是 JSON 对象")
        }
        object["watched"] = watched
        let body = try JSONSerialization.data(withJSONObject: object)
        let data = try await http.data("/records/\(id)", method: "PUT", body: body)
        return try decodeRecord(data, label: "幕间更新观看状态")
    }

    /// 录入一场演出。`date` 用 unix 秒，服务端要求 name 与 date 至少有一个。
    func create(_ draft: MujianRecordDraft) async throws -> MujianRecord {
        var payload: [String: Any] = ["name": draft.name, "date": draft.dateUnix]
        if !draft.city.isEmpty { payload["city"] = draft.city }
        if !draft.venue.isEmpty { payload["address"] = draft.venue }
        if !draft.seat.isEmpty { payload["seat"] = draft.seat }
        if !draft.remark.isEmpty { payload["remark"] = draft.remark }
        if !draft.categoryNames.isEmpty { payload["categoryNames"] = draft.categoryNames }
        if draft.duration > 0 { payload["duration"] = draft.duration }
        if let price = draft.price { payload["price"] = price }

        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await http.data("/records", method: "POST", body: body)
        return try decodeRecord(data, label: "幕间录入演出")
    }

    func categories() async throws -> [MujianCategory] {
        try await decode("/categories", label: "幕间剧种")
    }

    // MARK: - 解码

    private func decode<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        label: String
    ) async throws -> T {
        let data = try await http.data(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("\(label)：\(error.localizedDescription)")
        }
    }

    private func decodeRecord(_ data: Data, label: String) throws -> MujianRecord {
        do {
            return try JSONDecoder().decode(MujianRecord.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("\(label)：\(error.localizedDescription)")
        }
    }
}

/// 录入表单的本地状态。只放服务端认得的字段。
struct MujianRecordDraft: Equatable, Sendable {
    var name: String = ""
    var date: Date = .now
    var city: String = ""
    var venue: String = ""
    var seat: String = ""
    var remark: String = ""
    var categoryNames: [String] = []
    var duration: Int = 0
    var price: Double?

    var dateUnix: Int64 { Int64(date.timeIntervalSince1970) }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
