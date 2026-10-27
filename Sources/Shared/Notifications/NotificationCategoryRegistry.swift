import Foundation
import UserNotifications

/// 通知类别的合并入口。
///
/// 原先消息、演出、接入三处各自 `setNotificationCategories([category])`，
/// 后注册的会把前面的整组替换掉（消息上的“打开”按钮因此会消失）。
/// 统一在这里累加，只设置一次完整集合。
@MainActor
enum NotificationCategoryRegistry {

    private static var categories: [String: UNNotificationCategory] = [:]

    static func register(_ category: UNNotificationCategory, center: UNUserNotificationCenter) {
        categories[category.identifier] = category
        center.setNotificationCategories(Set(categories.values))
    }
}
