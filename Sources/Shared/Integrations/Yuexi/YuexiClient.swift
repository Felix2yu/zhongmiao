import Foundation
import ZhongmiaoCore

struct YuexiClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, cookie: String) {
        self.http = IntegrationHTTP(
            baseURL: baseURL,
            basePath: "",
            cookie: cookie,
            // 月汐的写接口是表单端点，成功后 303 重定向回页面。
            allowsRedirect: true
        )
    }

    func status() async throws -> YuexiNotificationStatus {
        let data = try await http.data("/api/notification/status")
        do {
            return try JSONDecoder().decode(YuexiNotificationStatus.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("月汐提醒状态：\(error.localizedDescription)")
        }
    }

    func anomalies() async throws -> [YuexiAnomaly] {
        let data = try await http.data("/api/anomaly")
        // 服务端在没有异常时返回 JSON null（nil slice 直接编码成 null），
        // 按数组解码会报「未能读取数据，因为数据丢失」，把整页都拖垮。
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "null" { return [] }
        do {
            return try JSONDecoder().decode([YuexiAnomaly].self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("月汐异常提示：\(error.localizedDescription)")
        }
    }

    /// 某个月的经期记录、预测区间与人员。
    func records(year: Int, month: Int) async throws -> YuexiRecords {
        let data = try await http.data(
            "/api/records",
            query: [
                URLQueryItem(name: "year", value: String(year)),
                URLQueryItem(name: "month", value: String(month))
            ]
        )
        do {
            return try JSONDecoder().decode(YuexiRecords.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("月汐记录：\(error.localizedDescription)")
        }
    }

    /// 记一次经期。服务端是表单端点（application/x-www-form-urlencoded），
    /// 成功后 303 重定向回页面。
    func createRecord(
        personID: Int64,
        startDate: String,
        endDate: String?,
        note: String
    ) async throws {
        var fields: [(String, String)] = [
            ("person_id", String(personID)),
            ("start_date", startDate),
            ("note", note)
        ]
        if let endDate, !endDate.isEmpty {
            fields.append(("end_date", endDate))
        }
        try await http.send(
            "/record/create",
            method: "POST",
            body: Data(Self.form(fields).utf8),
            contentType: "application/x-www-form-urlencoded"
        )
    }

    /// 添加记录人（谁在记）。也是表单端点。
    func createPerson(name: String, cycleLength: Int, periodLength: Int) async throws {
        let fields: [(String, String)] = [
            ("name", name),
            ("cycle_length", String(cycleLength)),
            ("period_length", String(periodLength))
        ]
        try await http.send(
            "/person/create",
            method: "POST",
            body: Data(Self.form(fields).utf8),
            contentType: "application/x-www-form-urlencoded"
        )
    }

    private static func form(_ fields: [(String, String)]) -> String {
        fields
            .map { name, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(name)=\(encoded)"
            }
            .joined(separator: "&")
    }
}
