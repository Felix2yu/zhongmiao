import Foundation

public struct CareReminderInput: Hashable, Sendable {

    public var id: Int
    public var plantName: String
    public var title: String
    public var nextDue: Date
    public var active: Bool

    public init(id: Int, plantName: String, title: String, nextDue: Date, active: Bool) {
        self.id = id
        self.plantName = plantName
        self.title = title
        self.nextDue = nextDue
        self.active = active
    }
}

/// 青野按到期日汇总成每日一条摘要，避免同一天十几条浇水提醒。
public enum QingyeReminderPlanner {

    public static func plan(
        tasks: [CareReminderInput],
        hour: Int,
        minute: Int,
        now: Date = .now,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        let today = QiansiLocalDate.startOfDay(now, timeZone: timeZone, calendar: calendar)
        var grouped: [Date: [CareReminderInput]] = [:]

        for task in tasks where task.active {
            let dueDay = QiansiLocalDate.startOfDay(task.nextDue, timeZone: timeZone, calendar: calendar)
            let target = max(dueDay, today)
            grouped[target, default: []].append(task)
        }

        return grouped.compactMap { day, items -> PlannedReminder? in
            guard let fireDate = QiansiLocalDate.date(
                on: day,
                hour: hour,
                minute: minute,
                timeZone: timeZone,
                calendar: calendar
            ), fireDate > now else {
                return nil
            }

            let ordered = items.sorted { lhs, rhs in
                if lhs.nextDue == rhs.nextDue { return lhs.id < rhs.id }
                return lhs.nextDue < rhs.nextDue
            }
            let labels = ordered.map { "\($0.plantName)\($0.title)" }
            let preview = labels.prefix(3).joined(separator: "、")
            let suffix = labels.count > 3 ? " 等 \(labels.count) 项" : ""
            let dayText = QiansiLocalDate.dayString(day, timeZone: timeZone, calendar: calendar)
            let isToday = calendar.isDate(day, inSameDayAs: now)

            return PlannedReminder(
                id: IntegrationReminderID.make(
                    serviceID: "qingye",
                    kind: "care",
                    key: dayText,
                    date: fireDate,
                    timeZone: timeZone
                ),
                serviceID: "qingye",
                title: isToday ? "今日养护" : "养护提醒",
                body: preview + suffix,
                fireDate: fireDate,
                userInfo: ["kind": "care", "day": dayText]
            )
        }
        .sorted { $0.fireDate < $1.fireDate }
    }
}
