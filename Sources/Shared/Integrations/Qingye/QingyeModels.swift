import Foundation

struct QingyeRoom: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var sort: Int?
    var isOutdoor: Bool?
    var icon: String?
    var count: Int?
}

struct QingyePlant: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var name: String
    var species: String?
    var photo: String?
    var roomId: Int
    var room: QingyeRoom?
    var note: String?
    var location: String?
    var acquiredDate: Date?
    var lightReq: String?
    var attributes: String?
    var createdAt: Date?
    var updatedAt: Date?
}

struct QingyeTask: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var plantId: Int
    var plant: QingyePlant?
    var type: String
    var title: String
    var intervalDays: Int
    var baseIntervalDays: Int?
    var lastDoneAt: Date?
    var nextDue: Date
    var active: Bool
    var createdAt: Date?
    var updatedAt: Date?

    var typeSymbol: String {
        switch type {
        case "water": "drop"
        case "fertilize": "leaf"
        case "mist": "cloud.drizzle"
        case "repot": "arrow.up.right.square"
        case "prune": "scissors"
        case "clean": "sparkles"
        case "pesticide": "ant"
        default: "ellipsis.circle"
        }
    }
}

struct QingyeCareLog: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var plantId: Int
    var plant: QingyePlant?
    var type: String
    var title: String
    var at: Date
    var note: String?
    var source: String?
    var taskId: Int?
}

struct QingyeSnapshot: Codable, Sendable {
    var rooms: [QingyeRoom]
    var plants: [QingyePlant]
    var tasks: [QingyeTask]
    var careLogs: [QingyeCareLog]
}

/// 新建植物的入参。字段与后端 plantBody 一一对应（roomId 用 0 表示未分房）。
struct QingyePlantDraft: Sendable {
    var name: String
    var species: String = ""
    var roomID: Int = 0
    var note: String = ""
    var location: String = ""
    var lightRequirement: String = ""
    var acquiredDate: String = ""
}

/// 养护指南：植物库匹配到的说明。匹配不到时 found 为 false。
struct QingyeCareGuide: Codable, Hashable, Sendable {
    var found: Bool
    var libraryId: Int?
    var name: String?
    var alias: String?
    var guide: String?
    var link: String?
}

enum QingyeDate {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw) {
                return date
            }
            if let date = dateOnlyFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析青野时间：\(raw)"
            )
        }
        return decoder
    }()

    static func string(from date: Date) -> String {
        fractionalFormatter.string(from: date)
    }

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }()

    nonisolated(unsafe) private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
