import EventKit
import Foundation
import ZhongmiaoCore

/// 系统日历里的演出。
///
/// 幕间自带 CalDAV（写方），同步过去的事件都落在名为「幕间」的日历里——
/// 这个显示名是硬编码的（见幕间 `internal/ics/ics.go` 的 `X-WR-CALNAME`），
/// 可以作为识别依据，比匹配标题关键词可靠得多。
///
/// **只读**。回写会与幕间的 CalDAV 同步打架，本类型不提供任何写入接口。
enum CalendarShowSource {

    struct AccessDenied: Error, Sendable, CustomStringConvertible {
        var description: String { "没有日历读取权限" }
    }

    /// 只读已授权的日历。未授权时直接抛错，**绝不在这里弹授权框**——
    /// 授权只由用户主动打开「读取系统日历」时经 `requestAccess()` 发起。
    static func fetchUpcoming(days: Int, keywords: [String]) async throws -> [Show] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw AccessDenied()
        }
        return EventStoreBox().read(days: days, keywords: keywords)
    }

    /// 用户主动打开开关时调用一次；已授权直接返回 true，不会重复弹窗。
    static func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        let box = EventStoreBox()
        return (try? await box.store.requestFullAccessToEvents()) ?? false
    }
}

// MARK: - 内部实现

/// `EKEventStore` 不是 `Sendable`，跨 await 使用会被 Swift 6 并发检查挡下。
/// 装箱成 `@unchecked Sendable` 是因为它的全部使用都在同一个函数体内顺序发生，
/// 不存在跨线程共享——这是 EventKit 的标准规避写法。
private final class EventStoreBox: @unchecked Sendable {
    let store = EKEventStore()

    func read(days: Int, keywords: [String]) -> [Show] {
        let calendar = Calendar.current
        let start = Date()
        guard let end = calendar.date(byAdding: .day, value: max(1, days), to: start) else {
            return []
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        return events.compactMap { event -> Show? in
            // 全天事件不是演出；已取消的更不该提醒。
            guard !event.isAllDay, event.status != .canceled else { return nil }
            guard isShow(event, keywords: keywords) else { return nil }
            return makeShow(event)
        }
    }

    /// 判断一个日历事件是不是演出。
    ///
    /// 两条判据取或：落在「幕间」日历里（默认路径），或命中用户填的关键词。
    /// 关键词为空时只走第一条——否则会把工作会议也当成演出。
    private func isShow(_ event: EKEvent, keywords: [String]) -> Bool {
        let calendarName = event.calendar.title
        if calendarName.localizedCaseInsensitiveContains("幕间") { return true }
        guard !keywords.isEmpty else { return false }

        let haystack = [event.title ?? "", calendarName, event.location ?? ""]
            .joined(separator: " ")
        return keywords.contains { haystack.localizedCaseInsensitiveContains($0) }
    }

    private func makeShow(_ event: EKEvent) -> Show? {
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // `eventIdentifier` 在同一台设备的日历数据库里稳定，够做通知去重键；
        // 它不跨设备、也不跨重新订阅，所以加前缀标明来源，便于排查。
        guard let identifier = event.eventIdentifier else { return nil }
        return Show(
            id: "cal-\(identifier)",
            name: title,
            venue: event.location,
            startsAt: event.startDate,
            endsAt: event.endDate,
            url: event.url,
            source: .calendar
        )
    }
}
