import Foundation
import ZhongmiaoCore

struct QingyeClient: Sendable {

    private let http: IntegrationHTTP

    init(baseURL: URL) {
        self.http = IntegrationHTTP(baseURL: baseURL, basePath: "/api")
    }

    func rooms() async throws -> [QingyeRoom] {
        try await get("/rooms")
    }

    func plants() async throws -> [QingyePlant] {
        try await get("/plants")
    }

    func upcomingTasks(days: Int = 14) async throws -> [QingyeTask] {
        try await get("/tasks/upcoming", query: [URLQueryItem(name: "days", value: String(days))])
    }

    func careLogs(limit: Int = 30) async throws -> [QingyeCareLog] {
        try await get("/care-logs", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func completeTask(id: Int, note: String) async throws -> QingyeTask {
        let body = try JSONEncoder().encode(NoteBody(note: note))
        return try await post("/tasks/\(id)/done", body: body)
    }

    func postponeTask(id: Int, days: Int, note: String) async throws -> QingyeTask {
        let body = try JSONEncoder().encode(PostponeBody(days: days, note: note))
        return try await post("/tasks/\(id)/postpone", body: body)
    }

    func addCareLog(
        plantID: Int,
        type: String,
        title: String,
        note: String,
        at: Date
    ) async throws -> QingyeCareLog {
        let body = try JSONEncoder().encode(
            CareLogBody(
                plantId: plantID,
                type: type,
                title: title,
                note: note,
                at: QingyeDate.string(from: at)
            )
        )
        return try await post("/care-logs", body: body)
    }

    private struct CareLogBody: Encodable {
        let plantId: Int
        let type: String
        let title: String
        let note: String
        let at: String
    }

    /// 新建植物。字段名与后端 plantBody 一一对应。
    func createPlant(_ draft: QingyePlantDraft) async throws -> QingyePlant {
        struct Body: Encodable {
            let name: String
            let species: String
            let photo: String
            let roomId: Int
            let note: String
            let location: String
            let lightReq: String
            let acquiredDate: String
            let attributes: String
        }
        let body = try JSONEncoder().encode(
            Body(
                name: draft.name,
                species: draft.species,
                photo: "",
                roomId: draft.roomID,
                note: draft.note,
                location: draft.location,
                lightReq: draft.lightRequirement,
                acquiredDate: draft.acquiredDate,
                attributes: ""
            )
        )
        return try await post("/plants", body: body)
    }

    /// 单株植物的完整档案。
    func plant(id: Int) async throws -> QingyePlant {
        try await get("/plants/\(id)")
    }

    /// 养护指南：植物库匹配不到时返回 nil。
    func careGuide(plantID: Int) async throws -> QingyeCareGuide? {
        let guide: QingyeCareGuide = try await get("/plants/\(plantID)/care-guide")
        return guide.found ? guide : nil
    }

    private struct NoteBody: Encodable {
        let note: String
    }
    private struct PostponeBody: Encodable {
        let days: Int
        let note: String
    }

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> T {
        try decode(try await http.data(path, query: query), path: path)
    }

    private func post<T: Decodable>(_ path: String, body: Data) async throws -> T {
        try decode(try await http.data(path, method: "POST", body: body), path: path)
    }

    private func decode<T: Decodable>(_ data: Data, path: String) throws -> T {
        let payload = try IntegrationEnvelope.unwrapCode(data)
        do {
            return try QingyeDate.decoder.decode(T.self, from: payload)
        } catch {
            throw IntegrationAPIError.decoding("青野 \(path)：\(error.localizedDescription)")
        }
    }
}
