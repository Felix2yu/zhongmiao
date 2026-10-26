#if os(macOS)
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.activate()
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshAuthorization()
    }

    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .zhongmiaoPushToken, object: token)
    }

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Task { @MainActor in
            AppModel.shared.appendLog("APNs 注册失败：\(error.localizedDescription)")
        }
    }
}
#endif
