import SwiftUI
import ZhongmiaoCore

@main
struct ZhongmiaoApp: App {

    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.refreshAuthorization()
                // 开岛要求 App 处于 active。冷启动时演出刷新是在 `didFinishLaunching`
                // 阶段发起的，那一刻场景还没激活，`Activity.request` 会被系统拒
                //（报错就是一句 `Target is not foreground`）。这里补一次对齐。
                Task { @MainActor in
                    await model.alignShowIsland()
                }
                // 回到前台：把离线期间积压的补发掉，并拉一次最新。
                model.syncNow(reason: "回到前台")
            case .background:
                model.persistOnBackground()
            default:
                break
            }
        }
    }
}
