import Foundation
import UserNotifications
import ZhongmiaoCore

/// 原生接入的本地提醒排程。与 `ShowScheduler` 共用系统通知中心，
/// 但用 `integration.` 前缀独立清理，互不干扰。
final class IntegrationReminderScheduler: @unchecked Sendable {

    static let categoryIdentifier = "im.yufei.zhongmiao.integration"
    static let openActionIdentifier = "im.yufei.zhongmiao.integration.open"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    @MainActor
    func registerCategory() {
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "查看",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        NotificationCategoryRegistry.register(category, center: center)
    }

    /// 幂等：同一 ID 重复排只会覆盖；已不存在的项按前缀清掉。
    func sync(serviceID: String, reminders: [PlannedReminder], enabled: Bool) async {
        let prefix = "\(IntegrationReminderID.prefix)\(serviceID)."
        let pending = await center.pendingNotificationRequests()
        let existing = Set(pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard enabled else {
            if !existing.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: Array(existing))
            }
            return
        }

        let budgeted = IntegrationReminderBudget.apply(to: reminders)
        let wanted = Set(budgeted.map(\.id))

        let stale = existing.subtracting(wanted)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        for reminder in budgeted where !existing.contains(reminder.id) {
            do {
                try await center.add(request(for: reminder))
            } catch {
                // 单条失败不影响其余提醒。
            }
        }

        await enforceTotalBudget()
    }

    func cancel(serviceID: String) async {
        let prefix = "\(IntegrationReminderID.prefix)\(serviceID)."
        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard !mine.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: mine)
    }

    func pendingCounts() async -> [String: Int] {
        let pending = await center.pendingNotificationRequests()
        var counts: [String: Int] = [:]
        for request in pending {
            guard let serviceID = IntegrationReminderID.serviceID(from: request.identifier) else { continue }
            counts[serviceID, default: 0] += 1
        }
        return counts
    }

    func pendingIdentifiers() async -> [String] {
        let pending = await center.pendingNotificationRequests()
        return pending.map(\.identifier).filter(IntegrationReminderID.isIntegrationID)
    }

    private func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = reminder.serviceID
        var info = reminder.userInfo
        info["integrationServiceID"] = reminder.serviceID
        content.userInfo = info

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
    }

    /// 系统对单个 App 的待处理通知上限是 64；这里给所有接入项留 48 的预算，
    /// 超出的按触发时间从最远处删。
    private func enforceTotalBudget() async {
        let pending = await center.pendingNotificationRequests()
        let mine = pending.filter { IntegrationReminderID.isIntegrationID($0.identifier) }
        guard mine.count > IntegrationReminderBudget.totalLimit else { return }

        let sorted = mine.sorted { lhs, rhs in
            let left = (lhs.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            let right = (rhs.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantFuture
            return left < right
        }
        let overflow = sorted
            .dropFirst(IntegrationReminderBudget.totalLimit)
            .map(\.identifier)
        if !overflow.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(overflow))
        }
    }
}
