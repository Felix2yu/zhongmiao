import Foundation

public struct AnniversaryReminderInput: Hashable, Sendable {

    public var id: String
    public var title: String
    public var personName: String?
    public var nextDate: Date
    public var daysUntil: Int
    public var remindDays: [Int]

    public init(
        id: String,
        title: String,
        personName: String? = nil,
        nextDate: Date,
        daysUntil: Int,
        remindDays: [Int]
    ) {
        self.id = id
        self.title = title
        self.personName = personName
        self.nextDate = nextDate
        self.daysUntil = daysUntil
        self.remindDays = remindDays
    }
}

public struct EventReminderInput: Hashable, Sendable {

    public var id: String
    public var title: String
    public var date: Date
    public var people: [String]

    public init(id: String, title: String, date: Date, people: [String] = []) {
        self.id = id
        self.title = title
        self.date = date
        self.people = people
    }
}

public struct CustomReminderInput: Hashable, Sendable {

    public var id: String
    public var title: String
    public var dueAt: Date
    public var personName: String?

    public init(id: String, title: String, dueAt: Date, personName: String? = nil) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.personName = personName
    }
}

/// 牵丝的提醒规则：
/// - 生日/纪念日沿用服务端的 `remind_days`（如 7,3,1,0），每档一条；
/// - 约会按全局“提前天数”一条；
/// - 自定义提醒按 `due_at`，date-only 的用全局时刻。
public enum QiansiReminderPlanner {

    public static func plan(
        anniversaries: [AnniversaryReminderInput],
        events: [EventReminderInput],
        customReminders: [CustomReminderInput],
        hour: Int,
        minute: Int,
        eventLeadDays: Int,
        now: Date = .now,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var plans: [PlannedReminder] = []

        for anniversary in anniversaries {
            let base = QiansiLocalDate.startOfDay(anniversary.nextDate, timeZone: timeZone, calendar: calendar)
            let offsets = Set(anniversary.remindDays.filter { (0...365).contains($0) }).sorted()

            for offset in offsets {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: base),
                      let fireDate = QiansiLocalDate.date(
                        on: day,
                        hour: hour,
                        minute: minute,
                        timeZone: timeZone,
                        calendar: calendar
                      ),
                      fireDate > now else {
                    continue
                }

                let remaining = max(0, offset)
                let who = anniversary.personName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = who.isEmpty ? anniversary.title : "\(who) · \(anniversary.title)"
                plans.append(
                    PlannedReminder(
                        id: IntegrationReminderID.make(
                            serviceID: "qiansi",
                            kind: "anniversary",
                            key: "\(anniversary.id)-\(offset)",
                            date: day,
                            timeZone: timeZone
                        ),
                        serviceID: "qiansi",
                        title: title,
                        body: remaining == 0 ? "就是今天" : "还有 \(remaining) 天",
                        fireDate: fireDate,
                        userInfo: ["kind": "anniversary", "id": anniversary.id]
                    )
                )
            }
        }

        for event in events {
            let base = QiansiLocalDate.startOfDay(event.date, timeZone: timeZone, calendar: calendar)
            guard let day = calendar.date(byAdding: .day, value: -max(0, eventLeadDays), to: base),
                  let fireDate = QiansiLocalDate.date(
                    on: day,
                    hour: hour,
                    minute: minute,
                    timeZone: timeZone,
                    calendar: calendar
                  ),
                  fireDate > now else {
                continue
            }

            let people = event.people.filter { !$0.isEmpty }.joined(separator: "、")
            let dateText = QiansiLocalDate.dayString(base, timeZone: timeZone, calendar: calendar)
            plans.append(
                PlannedReminder(
                    id: IntegrationReminderID.make(
                        serviceID: "qiansi",
                        kind: "event",
                        key: event.id,
                        date: day,
                        timeZone: timeZone
                    ),
                    serviceID: "qiansi",
                    title: "约会 · \(event.title)",
                    body: people.isEmpty ? dateText : "\(dateText) · \(people)",
                    fireDate: fireDate,
                    userInfo: ["kind": "event", "id": event.id]
                )
            )
        }

        for reminder in customReminders {
            let components = calendar.dateComponents([.hour, .minute], from: reminder.dueAt)
            let isMidnight = (components.hour ?? 0) == 0 && (components.minute ?? 0) == 0
            guard let fireDate = isMidnight
                ? QiansiLocalDate.date(
                    on: reminder.dueAt,
                    hour: hour,
                    minute: minute,
                    timeZone: timeZone,
                    calendar: calendar
                )
                : reminder.dueAt,
                fireDate > now else {
                continue
            }

            plans.append(
                PlannedReminder(
                    id: IntegrationReminderID.make(
                        serviceID: "qiansi",
                        kind: "reminder",
                        key: reminder.id,
                        date: fireDate,
                        timeZone: timeZone
                    ),
                    serviceID: "qiansi",
                    title: reminder.title,
                    body: reminder.personName ?? "牵丝提醒",
                    fireDate: fireDate,
                    userInfo: ["kind": "reminder", "id": reminder.id]
                )
            )
        }

        return plans.sorted { $0.fireDate < $1.fireDate }
    }
}
