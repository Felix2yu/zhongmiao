import Foundation
import ZhongmiaoCore

struct YuexiClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, cookie: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "", cookie: cookie)
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
        do {
            return try JSONDecoder().decode([YuexiAnomaly].self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("月汐异常提示：\(error.localizedDescription)")
        }
    }
}
