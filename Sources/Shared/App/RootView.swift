import Combine
import SwiftUI
import ZhongmiaoCore

struct RootView: View {

    /// 兼容旧名：三页骨架的取值类型。
    typealias Tab = AppSection

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var tab: AppSection = .catalog
    @State private var catalogPath = NavigationPath()
    @State private var inboxPath = NavigationPath()

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $catalogPath) {
                CatalogView()
                    .navigationDestination(for: AppModel.Route.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem { Label("应用", systemImage: "square.grid.2x2") }
            .tag(Tab.catalog)

            NavigationStack(path: $inboxPath) {
                NotificationsView()
                    .navigationDestination(for: AppModel.Route.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem { Label("通知", systemImage: "bell") }
            .badge(model.snapshot.unreadCount)
            .tag(Tab.inbox)

            #if os(iOS)
            // iOS 上设置仍是第三个标签；macOS 拆成了独立窗口（见 `ZhongmiaoApp` 的
            // `Settings` 场景），主窗口只剩应用与通知两页。
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(Tab.settings)
            #endif
        }
        #if os(macOS)
        // macOS 下窗口可以被拖到任意尺寸，最小尺寸必须由内容声明，
        // 否则 SwiftUI 会用「内容驱动的自然尺寸」开窗，窄窗里首页只剩一栏。
        .frame(minWidth: 720, minHeight: 480)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("设置（⌘,）")
                .accessibilityLabel("打开设置")
            }
        }
        #endif
        .task {
            // 冷启动时通知点击可能在首帧渲染前就到了，onChange 不会触发，
            // 这里补一次初始消费，避免丢掉深链。
            consumePendingRoute()
        }
        .onChange(of: model.pendingRoute) { _, _ in
            consumePendingRoute()
        }
        .overlay(alignment: .bottom) {
            toastOverlay
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .zmSelectSection)) { note in
            // 「视图」菜单的 ⌘1/2/3 只作用于当前窗口：多开时不该让所有窗口一起跳页。
            guard controlActiveState == .key,
                  let raw = note.userInfo?["section"] as? String,
                  let section = AppSection(rawValue: raw)
            else { return }
            // 设置已经是独立窗口，再当作标签切换会把 selection 指到不存在的页。
            if section == .settings {
                openSettings()
            } else {
                tab = section
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zmReloadPage)) { _ in
            reloadCurrentPage()
        }
        #endif
    }

    private func consumePendingRoute() {
        guard let route = model.pendingRoute else { return }
        tab = .catalog
        catalogPath.append(route)
        model.pendingRoute = nil
    }

    #if os(macOS)
    /// ⌘R 按当前页分派：进了服务页就重载网页，停在列表页就同步数据。
    private func reloadCurrentPage() {
        if catalogPath.count > 0 {
            NotificationCenter.default.post(name: .zmReloadWebPage, object: nil)
        } else {
            model.syncNow(reason: "菜单刷新")
        }
    }
    #endif

    @ViewBuilder
    private func destination(for route: AppModel.Route) -> some View {
        if let service = ServiceCatalog.service(id: route.serviceID), let url = model.url(for: route) {
            let preference = model.integrations.preference(for: service.id)
            let destination = IntegrationRouter.resolve(
                serviceID: service.id,
                hasExplicitURL: route.url != nil,
                preferWeb: route.preferWeb || preference.preferWeb,
                hasNativeTarget: route.target != nil
            )
            switch destination {
            case .native:
                NativeServiceScreen(service: service, target: route.target)
            case .web, .unconfigured:
                ServiceScreen(service: service, initialURL: url)
            }
        } else {
            ContentUnavailableView(
                "地址未配置",
                systemImage: "slash.circle",
                description: Text("「\(ServiceCatalog.service(id: route.serviceID)?.name ?? route.serviceID)」缺少可用地址，请到设置里检查接入方式。")
            )
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            Text(toast)
                .zmFont(.footnote, weight: .medium)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.separator, lineWidth: 0.5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, toastBottomInset)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        model.toast = nil
                    }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }

    /// iOS 要避开 26 的悬浮 Tab 栏；macOS 底部没有栏，76 会飘在半空。
    private var toastBottomInset: CGFloat {
        #if os(iOS)
        76
        #else
        24
        #endif
    }
}
