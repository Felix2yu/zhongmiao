import Foundation
import ZhongmiaoCore

struct QiansiClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL, token: String?) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api/v1", token: token)
    }

    func people(query: String = "") async throws -> [QiansiPerson] {
        var items = [URLQueryItem(name: "limit", value: "50")]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "q", value: trimmed))
        }
        return try await getList("/people", query: items, keys: ["people", "items"])
    }

    func anniversaries() async throws -> [QiansiAnniversary] {
        try await getList("/anniversaries", keys: ["anniversaries", "items"])
    }

    func upcomingReminders(days: Int = 30) async throws -> [QiansiReminder] {
        try await getList(
            "/reminders/upcoming",
            query: [URLQueryItem(name: "days", value: String(days))],
            keys: ["reminders", "items"]
        )
    }

    func events(from: Date, to: Date) async throws -> [QiansiEvent] {
        try await getList(
            "/events",
            query: [
                URLQueryItem(name: "from", value: QiansiLocalDate.dayString(from)),
                URLQueryItem(name: "to", value: QiansiLocalDate.dayString(to)),
                URLQueryItem(name: "limit", value: "50")
            ],
            keys: ["events", "items"]
        )
    }

    func dashboard() async throws -> QiansiStats {
        let data = try await http.data("/dashboard/stats")
        do {
            return try JSONDecoder().decode(QiansiStats.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("牵丝看板：\(error.localizedDescription)")
        }
    }

    func completeReminder(id: String) async throws {
        try await http.send(
            "/reminders/\(id)/done",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    func createAnniversary(
        title: String,
        date: String,
        personID: String?,
        isLunar: Bool,
        repeatYearly: Bool,
        remindDays: [Int]
    ) async throws -> QiansiAnniversary {
        let body = try JSONEncoder().encode(
            AnniversaryBody(
                person_id: personID,
                title: title,
                date: date,
                is_lunar: isLunar,
                repeat_yearly: repeatYearly,
                remind_days: remindDays.sorted().map(String.init).joined(separator: ",")
            )
        )
        return try await post("/anniversaries", body: body)
    }

    func createEvent(
        title: String,
        date: String,
        participantIDs: [String],
        location: String
    ) async throws -> QiansiEvent {
        let body = try JSONEncoder().encode(
            EventBody(
                title: title,
                event_date: date,
                participant_ids: participantIDs,
                locations: location.isEmpty ? [] : [location]
            )
        )
        return try await post("/events", body: body)
    }

    private struct AnniversaryBody: Encodable {
        let person_id: String?
        let title: String
        let date: String
        let is_lunar: Bool
        let repeat_yearly: Bool
        let remind_days: String
    }

    private struct EventBody: Encodable {
        let title: String
        let event_date: String
        let participant_ids: [String]
        let locations: [String]
    }

    private func getList<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        keys: [String]
    ) async throws -> [T] {
        let data = try await http.data(path, query: query)
        return try decodeList(data, path: path, keys: keys)
    }

    private func post<T: Decodable>(_ path: String, body: Data) async throws -> T {
        let data = try await http.data(path, method: "POST", body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw IntegrationAPIError.decoding("牵丝 \(path)：\(error.localizedDescription)")
        }
    }

    private func decodeList<T: Decodable>(_ data: Data, path: String, keys: [String]) throws -> [T] {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([T].self, from: data) {
            return list
        }
        if let object = try? decoder.decode([String: [T]].self, from: data) {
            for key in keys {
                if let list = object[key] { return list }
            }
            if let list = object.values.first { return list }
        }
        if data == Data("null".utf8) { return [] }
        throw IntegrationAPIError.decoding("牵丝 \(path) 列表格式不符")
    }
}
