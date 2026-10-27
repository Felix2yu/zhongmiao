import SwiftUI
import ZhongmiaoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// 承载单个自建应用的页面。
struct ServiceScreen: View {

    let service: ServiceDefinition
    let initialURL: URL

    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var web: WebAppModel
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case settings
        case ntfyTopics

        var id: String { rawValue }
    }

    init(service: ServiceDefinition, initialURL: URL) {
        self.service = service
        self.initialURL = initialURL
        _web = State(initialValue: WebAppModel(service: service, initialURL: initialURL))
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebViewHost(model: web)
                .background(Color.zmGrouped)

            if web.isLoading {
                ProgressView(value: min(max(web.progress, 0.05), 1))
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(.accentColor)
                    .animation(.easeOut(duration: 0.2), value: web.progress)
                    .transition(.opacity)
                    .accessibilityLabel("页面加载进度")
                    .accessibilityValue("\(Int(web.progress * 100))%")
            }

            if let failure = web.failure {
                Color.zmGrouped
                    .ignoresSafeArea()
                LoadFailureView(
                    title: failure.title,
                    detail: failure.detail,
                    retry: { web.reload() },
                    openInBrowser: { web.openCurrentInBrowser() }
                )
            }
        }
        .navigationTitle(web.displayTitle.isEmpty ? service.name : web.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // iOS 26 的悬浮 Tab 栏会占住底部，`.bottomBar` 工具栏不会顶替它、直接被丢掉。
        // 紧凑宽度下进页时收起 Tab 栏，浏览器工具条才会出现；返回后自动恢复。
        // iPad 的 Tab 栏在顶部，不冲突，保持原样。
        .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.network.isOnline && web.failure == nil {
                OfflineBanner(text: "离线浏览中 · 恢复网络后会自动刷新", showsProgress: false)
            }
        }
        .toolbar { toolbarContent }
        .onChange(of: model.settings.keepExternalLinksInApp) { _, value in
            web.updatePolicy(keepsExternalLinksInApp: value)
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online {
                web.reloadFromOrigin()
                model.appendLog("\(service.name)：网络恢复，刷新页面")
            }
        }
        .onChange(of: web.toast) { _, value in
            guard let value else { return }
            model.toast = value
            web.toast = nil
        }
        .task {
            web.updatePolicy(keepsExternalLinksInApp: model.settings.keepExternalLinksInApp)
            // 回调先接好再加载首屏，桥事件就不会在装配间隙丢失。
            await web.activate(
                onNotification: { model.ingest(webNotification: $0) },
                onLog: { model.appendLog($0) }
            )
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .settings:
                NavigationStack {
                    ServiceConfigView(service: service, showsDoneButton: true)
                }
            case .ntfyTopics:
                NavigationStack {
                    NtfyTopicsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { self.sheet = nil }
                            }
                        }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                web.goBack()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(!web.canGoBack)
            .accessibilityLabel("后退")

            Button {
                web.goForward()
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(!web.canGoForward)
            .accessibilityLabel("前进")

            Button {
                if web.isLoading {
                    web.stopLoading()
                } else {
                    web.reload()
                }
            } label: {
                Image(systemName: web.isLoading ? "xmark" : "arrow.clockwise")
            }
            .accessibilityLabel(web.isLoading ? "停止加载" : "重新加载")

            Spacer()

            ShareLink(item: web.currentURL ?? initialURL) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("分享当前页面")
        }
        #endif

        ToolbarItem(placement: .primaryAction) {
            Menu {
                if service.id == "ntfy" {
                    Button {
                        sheet = .ntfyTopics
                    } label: {
                        Label("浏览 ntfy 主题", systemImage: "list.bullet.rectangle")
                    }

                    Divider()
                }

                Button {
                    web.reloadFromOrigin()
                } label: {
                    Label("强制刷新（绕过缓存）", systemImage: "arrow.clockwise.circle")
                }

                Button {
                    web.openCurrentInBrowser()
                } label: {
                    Label("在浏览器打开", systemImage: "safari")
                }

                Button {
                    Pasteboard.copy((web.currentURL ?? initialURL).absoluteString)
                    model.toast = "地址已复制"
                } label: {
                    Label("复制地址", systemImage: "doc.on.doc")
                }

                Divider()

                Toggle(isOn: notificationBinding) {
                    Label("接收该应用通知", systemImage: "bell.badge")
                }

                Button {
                    model.probe(service)
                    model.toast = "正在检测 \(service.name)"
                } label: {
                    Label("检测连通性", systemImage: "waveform.path.ecg")
                }

                Button {
                    sheet = .settings
                } label: {
                    Label("服务设置", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("更多操作")
        }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { model.settings.preference(for: service).notificationsEnabled },
            set: { newValue in
                model.updateSettings { settings in
                    settings.update(service.id) { $0.notificationsEnabled = newValue }
                }
                if newValue {
                    model.syncNow(reason: "开启通知")
                }
            }
        )
    }
}
