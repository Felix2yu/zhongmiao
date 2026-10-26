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
