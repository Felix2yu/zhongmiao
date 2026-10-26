import Foundation
import UserNotifications

extension Notification.Name {
    /// AppDelegate 收到 APNs 设备令牌后广播（userInfo 里没有，直接以 String 作 object）。
    static let zhongmiaoPushToken = Notification.Name("im.yufei.zhongmiao.pushToken")
}

/// 通知交互代理：前台展示 + 点击跳转。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    typealias OpenHandler = @Sendable (String, String?) -> Void
    /// 演出通知上的按钮：`(actionIdentifier, showID)`。
    typealias ShowActionHandler = @Sendable (String, String) -> Void

    private let onOpen: OpenHandler
    private let onShowAction: ShowActionHandler

    init(onOpen: @escaping OpenHandler, onShowAction: @escaping ShowActionHandler) {
        self.onOpen = onOpen
        self.onShowAction = onShowAction
        super.init()
    }

    /// 前台也展示横幅：聚合应用的价值就在于"用户在别的服务里也能看到这条消息"。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo

        // 演出通知走另一条路：它不属于任何服务，没有 serviceID，
        // 「盯场」按钮要的是开岛而不是打开页面。
        if let showID = info["showID"] as? String, !showID.isEmpty {
            onShowAction(response.actionIdentifier, showID)
            return
        }

        guard let serviceID = info["serviceID"] as? String, !serviceID.isEmpty else { return }
        onOpen(serviceID, info["url"] as? String)
    }
}
