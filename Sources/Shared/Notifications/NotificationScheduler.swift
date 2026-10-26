import Foundation
import UserNotifications
import ZhongmiaoCore

/// 本地通知投递。
///
/// 这里承担了 PWA 在 iOS 上最薄弱的环节：
/// Web Push 在 WKWebView 里不可用，而 `ServiceWorkerRegistration.showNotification`
/// 也不会穿透到系统通知中心。于是统一改由原生调度——
/// 页面内通知走 JS 桥、离线补发走账本、远端推送走 APNs，最终都收敛到同一个调度器。
final class NotificationScheduler: @unchecked Sendable {

    static let openActionIdentifier = "im.yufei.zhongmiao.open"
    static let categoryIdentifier = "im.yufei.zhongmiao.message"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 是否允许投递。`ephemeral`（App Clip 场景）只在 iOS 存在。
    func isDeliveryAllowed() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional:
            return true
        case .ephemeral:
            #if os(iOS)
            return true
            #else
            return false
            #endif
        default:
            return false
        }
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        // 不主动要 provisional：用户按下按钮才申请，避免冷启动弹窗。
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    func registerCategories() {
        let open = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "打开",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    struct DeliveryOutcome: Sendable {
        var deliveredIDs: [String] = []
        var failed = 0
    }

    /// 逐条投递。使用 `item.id` 作为通知标识符——同一条事件重复投递时系统会自动替换，
    /// 不会在通知中心堆出多条重复通知。
    func deliver(_ items: [NotificationItem], serviceNames: [String: String]) async -> DeliveryOutcome {
        var outcome = DeliveryOutcome()
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.subtitle = serviceNames[item.serviceID] ?? ""
            content.threadIdentifier = item.serviceID
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [
                "itemID": item.id,
                "serviceID": item.serviceID,
                "url": item.url?.absoluteString ?? ""
            ]
            switch item.priority {
            case .passive:
                content.interruptionLevel = .passive
                content.sound = nil
            case .active:
                content.interruptionLevel = .active
                content.sound = .default
            case .timeSensitive:
                content.interruptionLevel = .timeSensitive
                content.sound = .default
            }
            let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
            do {
                try await center.add(request)
                outcome.deliveredIDs.append(item.id)
            } catch {
                outcome.failed += 1
            }
        }
        return outcome
    }

    func clearDelivered() async {
        center.removeAllDeliveredNotifications()
    }

    func setBadge(_ count: Int) async {
        do {
            try await center.setBadgeCount(max(0, count))
        } catch {
            // 用户关闭角标权限时忽略。
        }
    }
}
