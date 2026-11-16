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

    /// 界面缩放倍数：设置一改，三个窗口一起重算。
    private var scale: CGFloat {
        CGFloat(model.settings.interfaceScaleFactor)
    }

    var body: some Scene {
        #if os(macOS)
        // 1180 × 760 是设计稿里的初始窗口：内容宽 1132，首页正好排 3 栏。
        // 最小尺寸由 `RootView` 的 frame 声明，`.contentMinSize` 让它生效。
        windowScene
            .defaultSize(width: 1180, height: 760)
            .windowResizability(.contentMinSize)
            .commands { MacCommands(model: model) }

        // 「帮助 → 诊断与日志」的独立窗口。不占主窗口的导航栈，也不打断正在看的页面。
        // 关掉状态恢复：诊断窗口是临时用途，跟着下次启动自动弹出来只会添乱。
        Window("诊断与日志", id: MacWindow.diagnostics) {
            NavigationStack {
                DiagnosticsView()
            }
            .environment(model)
            .zmInterfaceScale(scale)
            .frame(minWidth: 560, minHeight: 480)
        }
        .restorationBehavior(.disabled)

        // 设置从主窗口的第三个标签拆出来，成为独立的设置窗口：⌘, 打开、关掉不影响主窗口。
        // 这是 macOS 的惯例（系统设置、各家 App 都这样），也省得设置页和标签栏抢同一根顶边。
        Settings {
            SettingsView()
                .environment(model)
                .zmInterfaceScale(scale)
                .frame(width: 820, height: 720)
        }
        #else
        windowScene
        #endif
    }

    private var windowScene: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // 界面缩放走环境值：所有原生视图的字号与度量都按它重算。
                .zmInterfaceScale(scale)
                .task { await model.bootstrap() }
                // 自定义 URL scheme 的入口（免费账号没有 Universal Links）。
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
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
