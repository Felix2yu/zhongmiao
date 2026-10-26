import Foundation
import UserNotifications

extension Notification.Name {
    /// AppDelegate 收到 APNs 设备令牌后广播（userInfo 里没有，直接以 String 作 object）。
    static let zhongmiaoPushToken = Notification.Name("im.yufei.zhongmiao.pushToken")
}

/// 通知交互代理：前台展示 + 点击跳转。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    typealias OpenHandler = @Sendable (String, String?) -> Void

    private let onOpen: OpenHandler

    init(onOpen: @escaping OpenHandler) {
        self.onOpen = onOpen
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
        guard let serviceID = info["serviceID"] as? String, !serviceID.isEmpty else { return }
        onOpen(serviceID, info["url"] as? String)
    }
}
