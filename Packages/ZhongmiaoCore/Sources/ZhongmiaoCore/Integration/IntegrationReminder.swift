import Foundation

/// 交给本地通知调度器的一条计划。各应用把 DTO 映射成这个结构，调度器只负责排程。
public struct PlannedReminder: Identifiable, Hashable, Sendable {

    public var id: String
    public var serviceID: String
    public var title: String
    public var body: String
    public var fireDate: Date
    public var userInfo: [String: String]
    /// 点通知时直接打开原生页里的这一条。
    public var target: NativeTarget?

    public init(
        id: String,
        serviceID: String,
        title: String,
        body: String,
        fireDate: Date,
        userInfo: [String: String] = [:],
        target: NativeTarget? = nil
    ) {
        self.id = id
        self.serviceID = serviceID
        self.title = title
        self.body = body
        self.fireDate = fireDate
        self.target = target
        var info = userInfo
        // 目标直接写进 userInfo，调度器不用各自记得塞键。
        if let target, !target.isEmpty {
            for (key, value) in NativeTargetKeys.userInfo(for: target) {
                info[key] = value
            }
        }
        self.userInfo = info
    }
}

public enum IntegrationReminderID {

    public static let prefix = "integration."

    public static func make(
        serviceID: String,
        kind: String,
        key: String,
        date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        "\(prefix)\(serviceID).\(kind).\(sanitize(key)).\(dayString(date, timeZone: timeZone))"
    }

    public static func isIntegrationID(_ identifier: String) -> Bool {
        identifier.hasPrefix(prefix)
    }

    public static func serviceID(from identifier: String) -> String? {
        guard isIntegrationID(identifier) else { return nil }
        let parts = identifier.dropFirst(prefix.count).split(separator: ".")
        return parts.first.map(String.init)
    }

    public static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    public static func sanitize(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = key.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let cleaned = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let result = cleaned.isEmpty ? "item" : cleaned
        return String(result.prefix(40))
    }
}

public enum IntegrationReminderBudget {

    public static let perServiceLimit = 12
    public static let totalLimit = 48

    /// 过期项丢掉、按 id 去重、按时间排序，再按每应用与总量截断。
    public static func apply(
        to reminders: [PlannedReminder],
        now: Date = .now
    ) -> [PlannedReminder] {
        var seen: Set<String> = []
        let sorted = reminders
            .filter { $0.fireDate > now }
            .sorted { lhs, rhs in
                if lhs.fireDate == rhs.fireDate { return lhs.id < rhs.id }
                return lhs.fireDate < rhs.fireDate
            }

        var perService: [String: Int] = [:]
        var result: [PlannedReminder] = []
        for reminder in sorted {
            guard !seen.contains(reminder.id) else { continue }
            let used = perService[reminder.serviceID, default: 0]
            guard used < perServiceLimit else { continue }
            guard result.count < totalLimit else { break }
            seen.insert(reminder.id)
            perService[reminder.serviceID] = used + 1
            result.append(reminder)
        }
        return result
    }
}
