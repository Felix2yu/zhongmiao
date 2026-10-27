import Foundation
import ZhongmiaoCore

struct ShenshiClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, token: String) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api", token: token)
    }

    func tasks(smart: String) async throws -> [ShenshiTask] {
        let data = try await http.data(
            "/tasks",
            query: [
                URLQueryItem(name: "smart", value: smart),
                URLQueryItem(name: "limit", value: "50")
            ]
        )
        do {
            return try JSONDecoder().decode(ShenshiTasksResponse.self, from: data).tasks
        } catch {
            throw IntegrationAPIError.decoding("慎始任务：\(error.localizedDescription)")
        }
    }

    func habits() async throws -> ShenshiHabitBoard {
        let data = try await http.data("/habits")
        do {
            return try JSONDecoder().decode(ShenshiHabitBoard.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("慎始习惯：\(error.localizedDescription)")
        }
    }

    func reminders() async throws -> [ShenshiReminderHit] {
        let data = try await http.data(
            "/reminders/due",
            query: [URLQueryItem(name: "lookahead", value: "1440")]
        )
        do {
            return try JSONDecoder().decode(ShenshiRemindersResponse.self, from: data).reminders
        } catch {
            throw IntegrationAPIError.decoding("慎始提醒：\(error.localizedDescription)")
        }
    }

    func stats() async throws -> ShenshiStats {
        let data = try await http.data(
            "/stats",
            query: [URLQueryItem(name: "days", value: "30")]
        )
        do {
            return try JSONDecoder().decode(ShenshiStats.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("慎始统计：\(error.localizedDescription)")
        }
    }

    func setDone(taskID: Int64, completed: Bool) async throws {
        let body = try JSONEncoder().encode(DoneBody(completed: completed))
        try await http.send("/tasks/\(taskID)/done", method: "POST", body: body)
    }

    func checkHabit(id: Int64) async throws {
        try await http.send("/habits/\(id)/check", method: "POST", body: Data("{}".utf8))
    }

    private struct DoneBody: Encodable {
        let completed: Bool
    }
}
