import Foundation

struct ShenshiTask: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var title: String
    var notes: String?
    var status: String?
    var priority: Int?
    var dueDate: String?
    var dueTime: String?
    var remindAt: String?
    var listName: String?
    var completedAt: String?
    var subtaskDone: Int?
    var subtaskOpen: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status, priority
        case dueDate = "dueDate"
        case dueTime = "dueTime"
        case remindAt = "remindAt"
        case listName = "listName"
        case completedAt = "completedAt"
        case subtaskDone = "subtaskDone"
        case subtaskOpen = "subtaskOpen"
    }

    var isDone: Bool { status == "done" }
}

struct ShenshiTasksResponse: Codable, Sendable {
    var tasks: [ShenshiTask]
    var count: Int?
}

struct ShenshiHabit: Codable, Hashable, Sendable, Identifiable {
    var id: Int64
    var name: String
    var icon: String?
    var cadence: String?
    var weekdays: String?
    var target: Int?
    var archived: Bool?
}

struct ShenshiHabitStat: Codable, Hashable, Sendable {
    var habitId: Int64
    var streak: Int?
    var today: Int?
    var rate: Double?
    var due: Int?

    enum CodingKeys: String, CodingKey {
        case habitId, streak, today, rate, due
    }
}

struct ShenshiHabitBoard: Codable, Sendable {
    var habits: [ShenshiHabit]
    var stats: [ShenshiHabitStat]?
}

struct ShenshiReminderHit: Codable, Hashable, Sendable {
    var task: ShenshiTask
    var ackId: Int64
    var fireAt: String
    var dueLabel: String?
    var overdue: Bool?

    enum CodingKeys: String, CodingKey {
        case task, fireAt, dueLabel, overdue
        case ackId = "ackId"
    }
}

struct ShenshiRemindersResponse: Codable, Sendable {
    var reminders: [ShenshiReminderHit]
}

struct ShenshiStats: Codable, Hashable, Sendable {
    var totalOpen: Int?
    var dueToday: Int?
    var overdue: Int?
    var doneToday: Int?
    var streakDays: Int?
    var completion: Double?

    enum CodingKeys: String, CodingKey {
        case totalOpen, dueToday, overdue, doneToday, streakDays, completion
    }
}

struct ShenshiSnapshot: Codable, Sendable {
    var today: [ShenshiTask]
    var overdue: [ShenshiTask]
    var habits: [ShenshiHabit]
    var habitStats: [ShenshiHabitStat]
    var reminders: [ShenshiReminderHit]
    var stats: ShenshiStats?
}

enum ShenshiDate {

    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }
}
