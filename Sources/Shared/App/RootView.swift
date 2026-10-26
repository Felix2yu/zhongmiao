import SwiftUI
import ZhongmiaoCore

struct RootView: View {

    enum Tab: Hashable {
        case catalog, inbox, diagnostics, settings
    }

    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .catalog
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

            NavigationStack {
                DiagnosticsView()
            }
            .tabItem { Label("体检", systemImage: "stethoscope") }
            .tag(Tab.diagnostics)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(Tab.settings)
        }
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
    }

    private func consumePendingRoute() {
        guard let route = model.pendingRoute else { return }
        tab = .catalog
        catalogPath.append(route)
        model.pendingRoute = nil
    }

    @ViewBuilder
    private func destination(for route: AppModel.Route) -> some View {
        if let service = ServiceCatalog.service(id: route.serviceID), let url = model.url(for: route) {
            ServiceScreen(service: service, initialURL: url)
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
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.separator, lineWidth: 0.5)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 76)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation(.easeOut(duration: 0.2)) {
                        model.toast = nil
                    }
                }
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
