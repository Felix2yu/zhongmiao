import Foundation

/// 牵丝的业务时间是“本地墙钟、不带时区”的字符串。
///
/// 例如 `2026-11-01T09:00:00`、`2026-11-01T09:00`、`2026-11-01`。
/// 这类值不能用 `ISO8601DateFormatter`（它会要求 offset），必须在指定时区里解析。
public enum QiansiLocalDate {

    public static let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSS",
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd"
    ]

    public static func parse(
        _ raw: String,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // DateFormatter 会宽松地接受 `2026/11/01` 这类分隔符，先用形状做一次硬校验。
        let shape = #"^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?)?$"#
        guard trimmed.range(of: shape, options: .regularExpression) != nil else {
            return nil
        }

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.calendar = calendar
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    public static func dayString(
        _ date: Date,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func startOfDay(
        _ date: Date,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date)
    }

    public static func daysUntil(
        _ date: Date,
        now: Date = .now,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> Int {
        var calendar = calendar
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    /// 把某个日期的时分替换成指定时刻，用于“全局提醒时刻”。
    public static func date(
        on day: Date,
        hour: Int,
        minute: Int,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) -> Date? {
        var calendar = calendar
        calendar.timeZone = timeZone
        return calendar.date(
            bySettingHour: min(max(hour, 0), 23),
            minute: min(max(minute, 0), 59),
            second: 0,
            of: day
        )
    }
}
