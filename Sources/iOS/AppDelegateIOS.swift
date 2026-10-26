#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 通知代理与网络监听必须尽早挂上，否则冷启动期间的点击事件会丢。
        AppModel.shared.activate()
        BackgroundSync.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppModel.shared.persistOnBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        AppModel.shared.refreshAuthorization()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .zhongmiaoPushToken, object: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Task { @MainActor in
            AppModel.shared.appendLog("APNs 注册失败：\(error.localizedDescription)")
        }
    }
}
#endif
