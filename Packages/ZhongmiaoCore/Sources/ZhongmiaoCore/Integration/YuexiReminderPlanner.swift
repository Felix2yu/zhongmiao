import Foundation

public struct YuexiReminderInput: Hashable, Sendable {

    public var name: String
    public var nextPeriod: Date
    public var daysLeft: Int

    public init(name: String, nextPeriod: Date, daysLeft: Int) {
        self.name = name
        self.nextPeriod = nextPeriod
        self.daysLeft = daysLeft
    }
}

/// 月汐的提醒只保留“有新的周期提醒”这类脱敏文案，
/// 具体日期不进入锁屏通知。
public enum YuexiReminderPlanner {

    public static func plan(
        upcoming: [YuexiReminderInput],
        daysBefore: Int,
        hour: Int,
        minute: Int,
        now: Date = .now,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        let today = QiansiLocalDate.startOfDay(now, timeZone: timeZone, calendar: calendar)
        let lead = max(0, daysBefore)

        return upcoming.compactMap { item -> PlannedReminder? in
            let base = QiansiLocalDate.startOfDay(item.nextPeriod, timeZone: timeZone, calendar: calendar)
            guard let leadDay = calendar.date(byAdding: .day, value: -lead, to: base) else {
                return nil
            }
            let target = max(leadDay, today)
            guard let fireDate = QiansiLocalDate.date(
                on: target,
                hour: hour,
                minute: minute,
                timeZone: timeZone,
                calendar: calendar
            ), fireDate > now else {
                return nil
            }

            let day = QiansiLocalDate.dayString(target, timeZone: timeZone, calendar: calendar)
            return PlannedReminder(
                id: IntegrationReminderID.make(
                    serviceID: "yuexi",
                    kind: "cycle",
                    key: item.name,
                    date: fireDate,
                    timeZone: timeZone
                ),
                serviceID: "yuexi",
                title: "月汐提醒",
                body: "有新的周期提醒",
                fireDate: fireDate,
                userInfo: ["kind": "cycle", "day": day]
            )
        }
        .sorted { $0.fireDate < $1.fireDate }
    }
}
