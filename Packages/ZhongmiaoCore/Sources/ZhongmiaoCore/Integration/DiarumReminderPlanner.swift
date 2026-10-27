import Foundation

/// 吾身只做“今天还没写”的当天提醒。
/// 写日记仍走网页版，原生不承担整段正文覆盖的风险。
public enum DiarumReminderPlanner {

    public static func plan(
        hasEntryToday: Bool,
        hour: Int,
        minute: Int,
        now: Date = .now,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        guard !hasEntryToday else { return [] }
        let today = QiansiLocalDate.startOfDay(now, timeZone: timeZone, calendar: calendar)
        guard let fireDate = QiansiLocalDate.date(
            on: today,
            hour: hour,
            minute: minute,
            timeZone: timeZone,
            calendar: calendar
        ), fireDate > now else {
            return []
        }

        let day = QiansiLocalDate.dayString(today, timeZone: timeZone, calendar: calendar)
        return [
            PlannedReminder(
                id: IntegrationReminderID.make(
                    serviceID: "diarum",
                    kind: "write",
                    key: day,
                    date: fireDate,
                    timeZone: timeZone
                ),
                serviceID: "diarum",
                title: "今天还没写日记",
                body: "花几分钟记下今天。",
                fireDate: fireDate,
                userInfo: ["kind": "write", "day": day],
                target: NativeTarget(kind: "diary", identifier: day)
            )
        ]
    }
}
