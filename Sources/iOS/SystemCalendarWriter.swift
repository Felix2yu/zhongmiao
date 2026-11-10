#if os(iOS)
import EventKit
import Foundation
import ZhongmiaoCore

/// 把提醒写进系统日历与提醒事项。
///
/// 为什么需要它：免费个人账号没有 APNs，本地通知又有 64 条上限，
/// 远期提醒（生日、纪念日、养护周期）既排不下、也依赖 App 曾经运行过。
/// 写进系统后由系统持有——App 被杀、描述文件过期都不影响到点触发。
///
/// **安全红线**：只在众妙自己创建的专用日历里操作。专用日历建不出来就整体跳过，
/// 绝不退到用户的默认日历里写入，更不会删除任何没有本文件写入的锚点标记的条目。
enum SystemCalendarWriter {

    struct Outcome: Sendable {
        var created = 0
        var updated = 0
        var removed = 0
        var failed = 0
        var message: String?

        var summary: String {
            var parts: [String] = []
            if created > 0 { parts.append("新建 \(created)") }
            if updated > 0 { parts.append("更新 \(updated)") }
            if removed > 0 { parts.append("清理 \(removed)") }
            if failed > 0 { parts.append("失败 \(failed)") }
            let body = parts.isEmpty ? "无变化" : parts.joined(separator: " / ")
            return message.map { "\(body)：\($0)" } ?? body
        }

        mutating func merge(_ other: Outcome) {
            created += other.created
            updated += other.updated
            removed += other.removed
            failed += other.failed
            message = message ?? other.message
        }
    }

    /// 专用日历名。用户能一眼看出这些条目是谁写进去的。
    static let calendarName = "众妙"

    /// 让系统里该服务的条目与当前计划一致：新增、更新、清理。
    /// 只在用户显式开启系统提醒后调用，因此可以按需申请对应通道的权限。
    static func sync(
        serviceID: String,
        anchors: [SystemAnchor]
    ) async -> Outcome {
        let planned = SystemAnchorBudget.apply(to: anchors)
        let box = EventStoreBox()

        let events = planned.filter { $0.channel == .calendar }
        let reminders = planned.filter { $0.channel == .reminder }

        var outcome = Outcome()
        if !events.isEmpty {
            outcome.merge(await syncEvents(box: box, serviceID: serviceID, anchors: events, enabled: true))
        }
        if !reminders.isEmpty {
            outcome.merge(await syncReminders(box: box, serviceID: serviceID, anchors: reminders, enabled: true))
        }
        return outcome
    }

    /// 关闭开关/清凭据时清理，不再申请任何权限。
    /// 只处理系统已经授予完全访问的通道；没授权、没建过专用列表就静默跳过。
    static func clear(serviceID: String) async -> Outcome {
        let box = EventStoreBox()
        var outcome = Outcome()

        if EKEventStore.authorizationStatus(for: .event) == .fullAccess,
           let calendar = box.existingEventCalendar() {
            outcome.merge(box.applyEvents(
                serviceID: serviceID,
                anchors: [],
                calendar: calendar,
                enabled: false
            ))
        }

        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
           let calendar = box.existingReminderCalendar() {
            outcome.merge(await box.applyReminders(
                serviceID: serviceID,
                anchors: [],
                calendar: calendar,
                enabled: false
            ))
        }

        return outcome
    }

    // MARK: - 日历事件

    private static func syncEvents(
        box: EventStoreBox,
        serviceID: String,
        anchors: [SystemAnchor],
        enabled: Bool
    ) async -> Outcome {
        guard let granted = try? await box.store.requestFullAccessToEvents(), granted else {
            return Outcome(message: "没有日历权限")
        }
        guard let target = box.resolveEventCalendar() else {
            return Outcome(failed: anchors.count, message: "建不出专用日历，已跳过写入")
        }

        return box.applyEvents(
            serviceID: serviceID,
            anchors: anchors,
            calendar: target,
            enabled: enabled
        )
    }

    // MARK: - 提醒事项

    private static func syncReminders(
        box: EventStoreBox,
        serviceID: String,
        anchors: [SystemAnchor],
        enabled: Bool
    ) async -> Outcome {
        guard let granted = try? await box.store.requestFullAccessToReminders(), granted else {
            return Outcome(message: "没有提醒事项权限")
        }
        guard let target = box.resolveReminderCalendar() else {
            return Outcome(failed: anchors.count, message: "建不出专用提醒列表，已跳过写入")
        }

        return await box.applyReminders(
            serviceID: serviceID,
            anchors: anchors,
            calendar: target,
            enabled: enabled
        )
    }
}

// MARK: - 内部实现

/// `EKEventStore` 不是 `Sendable`，跨 await 使用会被 Swift 6 并发检查挡下。
/// 装箱是 EventKit 的标准规避写法：全部使用都在同一处顺序发生，不存在跨线程共享。
private final class EventStoreBox: @unchecked Sendable {

    let store = EKEventStore()

    // MARK: 日历

    /// 只查找已有的众妙日历，不创建。用于关闭开关后的清理。
    func existingEventCalendar() -> EKCalendar? {
        store.calendars(for: .event)
            .first { $0.title == SystemCalendarWriter.calendarName && $0.allowsContentModifications }
    }

    /// 找到众妙的专用日历；没有就建一个。建不出来返回 nil——调用方据此整体跳过。
    func resolveEventCalendar() -> EKCalendar? {
        if let existing = existingEventCalendar() {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = SystemCalendarWriter.calendarName
        calendar.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        guard let source = calendar.source else { return nil }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            return nil
        }
    }

    /// 只查找已有的众妙提醒列表，不创建。用于关闭开关后的清理。
    func existingReminderCalendar() -> EKCalendar? {
        store.calendars(for: .reminder)
            .first { $0.title == SystemCalendarWriter.calendarName && $0.allowsContentModifications }
    }

    func resolveReminderCalendar() -> EKCalendar? {
        if let existing = existingReminderCalendar() {
            return existing
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = SystemCalendarWriter.calendarName
        calendar.source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .local }
        guard let source = calendar.source else { return nil }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            return nil
        }
    }

    // MARK: 事件

    func applyEvents(
        serviceID: String,
        anchors: [SystemAnchor],
        calendar: EKCalendar,
        enabled: Bool
    ) -> SystemCalendarWriter.Outcome {
        let prefix = "zm.\(serviceID)."
        let existing = indexedEvents(in: calendar, prefix: prefix)
        var outcome = SystemCalendarWriter.Outcome()

        guard enabled else {
            for (_, event) in existing {
                do {
                    let span: EKSpan = event.recurrenceRules?.isEmpty == false ? .futureEvents : .thisEvent
                    try store.remove(event, span: span)
                    outcome.removed += 1
                } catch {
                    outcome.failed += 1
                    outcome.message = outcome.message ?? "清理日历条目失败：\(error.localizedDescription)"
                }
            }
            return outcome
        }

        var wanted: Set<String> = []
        for anchor in anchors {
            wanted.insert(anchor.identifier)
            let event = existing[anchor.identifier] ?? makeEvent(in: calendar)
            // 年度事件在 EventKit 里是一串 occurrence，必须用 .futureEvents 更新/删除，
            // 否则只会改到这一个实例，后面的年份会留下旧标题或旧时间。
            let span: EKSpan = event.recurrenceRules?.isEmpty == false ? .futureEvents : .thisEvent
            event.title = anchor.title
            event.notes = anchor.markedNotes
            event.url = anchor.url
            event.isAllDay = anchor.isAllDay
            if anchor.isAllDay {
                event.startDate = Calendar.current.startOfDay(for: anchor.fireDate)
                event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)
            } else {
                event.startDate = anchor.fireDate
                event.endDate = anchor.fireDate.addingTimeInterval(30 * 60)
            }
            // 每年重复靠 recurrence rule：一次写入，之后每年由系统自己到点。
            event.recurrenceRules = anchor.repeatsYearly
                ? [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
                : nil
            // 全天与重复事件用相对偏移（事件发生时提醒）；有明确时刻的用绝对时间。
            event.alarms = anchor.isAllDay || anchor.repeatsYearly
                ? [EKAlarm(relativeOffset: 0)]
                : [EKAlarm(absoluteDate: anchor.fireDate)]

            do {
                try store.save(event, span: span)
                if existing[anchor.identifier] == nil { outcome.created += 1 } else { outcome.updated += 1 }
            } catch {
                outcome.failed += 1
                outcome.message = outcome.message ?? "写入日历失败：\(error.localizedDescription)"
            }
        }

        // 只清掉本服务、带锚点标记、且这一轮不再需要的条目。
        for (identifier, event) in existing where !wanted.contains(identifier) {
            do {
                let span: EKSpan = event.recurrenceRules?.isEmpty == false ? .futureEvents : .thisEvent
                try store.remove(event, span: span)
                outcome.removed += 1
            } catch {
                outcome.failed += 1
            }
        }
        return outcome
    }

    private func makeEvent(in calendar: EKCalendar) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        return event
    }

    /// 专用日历里已有的、属于本服务的条目，按锚点标识索引。
    private func indexedEvents(in calendar: EKCalendar, prefix: String) -> [String: EKEvent] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now
        let end = Calendar.current.date(byAdding: .year, value: 10, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])

        var result: [String: EKEvent] = [:]
        for event in store.events(matching: predicate) {
            guard let identifier = SystemAnchorMarker.extract(from: event.notes),
                  identifier.hasPrefix(prefix) else { continue }
            guard let current = result[identifier] else {
                result[identifier] = event
                continue
            }
            // 年度事件会返回多个 occurrence；优先拿“最近的未来一次”，
            // 这样 .futureEvents 的更新/删除会覆盖后续所有年份。
            let currentIsFuture = current.startDate >= now
            let eventIsFuture = event.startDate >= now
            if (!currentIsFuture && eventIsFuture)
                || (currentIsFuture && eventIsFuture && event.startDate < current.startDate) {
                result[identifier] = event
            }
        }
        return result
    }

    // MARK: 提醒事项

    /// 读取与写入必须在同一处完成：`EKReminder` 不是 `Sendable`，
    /// 把数组送过 continuation 边界会被 Swift 6 并发检查拦下，
    /// 所以这里只把 final 的 `Outcome`（纯值、可 Sendable）送回去。
    func applyReminders(
        serviceID: String,
        anchors: [SystemAnchor],
        calendar: EKCalendar,
        enabled: Bool
    ) async -> SystemCalendarWriter.Outcome {
        let predicate = store.predicateForReminders(in: [calendar])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let outcome = self.applyRemindersToStore(
                    serviceID: serviceID,
                    anchors: anchors,
                    calendar: calendar,
                    existing: reminders ?? [],
                    enabled: enabled
                )
                continuation.resume(returning: outcome)
            }
        }
    }

    func applyRemindersToStore(
        serviceID: String,
        anchors: [SystemAnchor],
        calendar: EKCalendar,
        existing fetched: [EKReminder],
        enabled: Bool
    ) -> SystemCalendarWriter.Outcome {
        let prefix = "zm.\(serviceID)."
        var indexed: [String: EKReminder] = [:]
        var mine: [EKReminder] = []
        for reminder in fetched {
            guard let identifier = SystemAnchorMarker.extract(from: reminder.notes),
                  identifier.hasPrefix(prefix) else { continue }
            indexed[identifier] = reminder
            mine.append(reminder)
        }

        var outcome = SystemCalendarWriter.Outcome()
        guard enabled else {
            for reminder in mine {
                do {
                    try store.remove(reminder, commit: true)
                    outcome.removed += 1
                } catch {
                    outcome.failed += 1
                    outcome.message = outcome.message ?? "清理提醒事项失败：\(error.localizedDescription)"
                }
            }
            return outcome
        }

        var wanted: Set<String> = []
        for anchor in anchors {
            wanted.insert(anchor.identifier)
            let reminder = indexed[anchor.identifier] ?? makeReminder(in: calendar)
            reminder.title = anchor.title
            // 提醒事项没有 url 字段，深链只能落在备注里。
            reminder.notes = anchor.markedNotes
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: anchor.fireDate
            )
            reminder.dueDateComponents = components
            reminder.startDateComponents = components
            reminder.alarms = [EKAlarm(absoluteDate: anchor.fireDate)]
            do {
                try store.save(reminder, commit: true)
                if indexed[anchor.identifier] == nil { outcome.created += 1 } else { outcome.updated += 1 }
            } catch {
                outcome.failed += 1
                outcome.message = outcome.message ?? "写入提醒事项失败：\(error.localizedDescription)"
            }
        }

        for (identifier, reminder) in indexed where !wanted.contains(identifier) {
            do {
                try store.remove(reminder, commit: true)
                outcome.removed += 1
            } catch {
                outcome.failed += 1
            }
        }
        return outcome
    }

    private func makeReminder(in calendar: EKCalendar) -> EKReminder {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        return reminder
    }
}
#endif
