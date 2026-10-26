import Foundation
import UserNotifications
import ZhongmiaoCore

/// 演出的本地提醒排程。
///
/// 这是**唯一可靠**的演出提醒通道：灵动岛窗口再宽也只有 8 小时、且何时开启不由我们决定，
/// 本地通知则能在 App 已被杀掉的情况下到点投递。所以它必须先做，岛只是增强。
///
/// 排程用 `UNCalendarNotificationTrigger`，按开演时间倒推提前量，
/// 与系统日历的提醒是同一套机制，因此同样不怕重启、不怕杀进程。
final class ShowScheduler: @unchecked Sendable {

    static let categoryIdentifier = "im.yufei.zhongmiao.show"
    /// 「盯场」：拉开演前的灵动岛。
    ///
    /// 必须带 `.foreground`——只有把 App 拉到前台才有机会执行开岛代码；
    /// 不带的话系统在后台直接吞掉，什么都不会发生。
    static let watchActionIdentifier = "im.yufei.zhongmiao.show.watch"
    static let openActionIdentifier = "im.yufei.zhongmiao.show.open"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// 通知标识符。加 `show.` 前缀是为了与消息通知的 id 空间分开，便于批量清理。
    static func identifier(for showID: String) -> String {
        "show.\(showID)"
    }

    func registerCategories() {
        let watch = UNNotificationAction(
            identifier: Self.watchActionIdentifier,
            title: "盯场",
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "查看详情",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [watch, open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    // MARK: - 排程

    /// 把缓存里的演出同步成系统排程。
    ///
    /// 幂等：同一场演出始终用同一个标识符，重复排只是覆盖，不会堆出多条。
    /// 已过期（`reminderDate` 为 nil）的场次不排——给三小时前开演的演出补一条提醒毫无意义。
    ///
    /// - Returns: 本次新增的条数。
    @discardableResult
    func sync(_ shows: [Show], lead: TimeInterval, now: Date = .now) async -> Int {
        let pending = await center.pendingNotificationRequests()
        let existing = Set(pending.map(\.identifier).filter { $0.hasPrefix("show.") })

        var wanted: Set<String> = []
        var added = 0

        for show in shows {
            guard let date = show.reminderDate(lead: lead, now: now) else { continue }
            let identifier = Self.identifier(for: show.id)
            wanted.insert(identifier)
            guard !existing.contains(identifier) else { continue }
            do {
                try await center.add(request(for: show, identifier: identifier, date: date))
                added += 1
            } catch {
                // 单条失败不影响其余场次：少一条提醒好过全部排不上。
            }
        }

        // 演出被取消、或已从缓存清掉的，撤掉排程——否则会提醒一场不存在的演出。
        let stale = existing.subtracting(wanted)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }
        return added
    }

    /// 撤掉全部演出提醒（总开关关闭时）。
    func cancelAll() async {
        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix("show.") }
        guard !mine.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    // MARK: - 内容

    private func request(for show: Show, identifier: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "《\(show.name)》\(Self.clock(show.startsAt))开演"
        content.body = [show.venue, show.seat]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if content.body.isEmpty {
            content.body = "还有 \(Self.hours(lead: show.startsAt.timeIntervalSince(date)))"
        }
        content.subtitle = "距开演 \(Self.hours(lead: show.startsAt.timeIntervalSince(date)))"
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        // 需要授权的能力，免费个人账号下可能被系统降级为普通通知。
        // 即便降级也照样投递，只是不穿透专注模式——所以不能依赖它做唯一保障。
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "showID": show.id,
            "url": show.url?.absoluteString ?? ""
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private static func clock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return minute == 0 ? "\(hour) 点" : "\(hour) 点 \(minute) 分"
    }

    private static func hours(lead: TimeInterval) -> String {
        let total = Int((lead / 3600).rounded())
        if total < 1 { return "不到 1 小时" }
        return "\(total) 小时"
    }
}
