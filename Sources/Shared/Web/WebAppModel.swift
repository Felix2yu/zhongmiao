import Foundation
import Observation
import WebKit
import ZhongmiaoCore

/// 单个服务页面的运行时状态，驱动工具栏、进度条与错误页。
///
/// 直接持有 iOS 26+ 的 `WebPage`：标题、进度、加载状态镜像自它的 `@Observable`
/// 属性，导航策略经 `WebNavigationDecider` 转发回来，页面内桥事件仍走 `WebBridgeHandler`。
@MainActor
@Observable
final class WebAppModel {

    struct LoadFailure: Equatable {
        var title: String
        var detail: String
        var isOffline: Bool
    }

    private(set) var title: String = ""
    private(set) var progress: Double = 0
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var currentURL: URL?
    private(set) var failure: LoadFailure?
    /// 一次性提示（下载完成、复制成功等）。
    var toast: String?

    var displayTitle: String {
        if !title.isEmpty { return title }
        return currentURL?.host ?? ""
    }

    /// 页面本体，由 `WebViewHost` 用 `WebView` 承载。
    let page: WebPage

    private let service: ServiceDefinition
    private let initialURL: URL
    private let serviceHost: String?
    /// 站外链接是否留在应用内（随设置变化，由 `ServiceScreen` 调 `updatePolicy` 同步）。
    private(set) var policy = WebContentPolicy()
    private let bridge = WebBridgeHandler()
    private var onNotification: ((NotificationItem) -> Void)?
    private var onLog: ((String) -> Void)?
    private var activated = false

    init(service: ServiceDefinition, initialURL: URL) {
        self.service = service
        self.initialURL = initialURL
        self.serviceHost = initialURL.host
        let decider = WebNavigationDecider()
        self.page = WebPage(
            configuration: WebViewFactory.makeConfiguration(service: service, bridge: bridge),
            navigationDecider: decider
        )
        decider.model = self
        bridge.onEvent = { [weak self] event in
            self?.handleBridgeEvent(event)
        }
    }

    /// 由 `ServiceScreen` 的 `.task` 启动：先接好回调，再加载首屏并长期监听导航事件。
    func activate(
        onNotification: @escaping (NotificationItem) -> Void,
        onLog: @escaping (String) -> Void
    ) async {
        guard !activated else { return }
        activated = true
        self.onNotification = onNotification
        self.onLog = onLog
        trackPageObservation()
        load(initialURL)
        await observeNavigations()
    }

    // MARK: - 操作

    func load(_ url: URL) {
        failure = nil
        page.load(URLRequest(url: url))
    }

    /// 普通重载：优先走 Service Worker 缓存（离线时仍能拿到外壳）。
    func reload() {
        failure = nil
        if page.url == nil {
            load(initialURL)
        } else {
            page.reload()
        }
    }

    /// 强制绕过缓存重载。网络恢复后用它拿最新版本。
    func reloadFromOrigin() {
        failure = nil
        page.reload(fromOrigin: true)
    }

    func goBack() {
        failure = nil
        if let item = page.backForwardList.backList.last {
            page.load(item)
        }
    }

    func goForward() {
        failure = nil
        if let item = page.backForwardList.forwardList.first {
            page.load(item)
        }
    }

    func stopLoading() {
        page.stopLoading()
    }

    /// 交给系统浏览器打开当前页（自签证书/PWA 安装等场景）。
    func openCurrentInBrowser() {
        Platform.openExternally(currentURL ?? page.url ?? initialURL)
    }

    /// 下拉刷新。等待加载结束，让系统刷新指示器停留到内容就绪。
    func pullToRefresh() async {
        reload()
        var waited = 0
        while isLoading && waited < 15_000 {
            try? await Task.sleep(for: .milliseconds(120))
            waited += 120
        }
    }

    // MARK: - 导航策略（由 WebNavigationDecider 转发）

    /// 设置里「站外链接在应用内打开」变化时同步导航策略。
    func updatePolicy(keepsExternalLinksInApp: Bool) {
        guard policy.keepsExternalLinksInApp != keepsExternalLinksInApp else { return }
        policy = WebContentPolicy(keepsExternalLinksInApp: keepsExternalLinksInApp)
    }

    func decideNavigationPolicy(for action: WebPage.NavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }

        // 新窗口（target="_blank" 等）没有承载对象：能留下的就在本页打开，站外交给浏览器。
        if action.target == nil {
            switch policy.decision(for: url, serviceHost: serviceHost) {
            case .allowInApp:
                page.load(URLRequest(url: url))
            case .openExternally:
                Platform.openExternally(url)
            case .cancel:
                break
            }
            return .cancel
        }

        switch policy.decision(for: url, serviceHost: serviceHost) {
        case .allowInApp:
            break
        case .openExternally:
            Platform.openExternally(url)
            return .cancel
        case .cancel:
            return .cancel
        }

        // 「预期中的下载」不交给系统，用 URLSession 落盘到下载目录，保持原有体验。
        if action.shouldPerformDownload {
            let request = action.request
            Task { await self.download(request) }
            return .cancel
        }
        return .allow
    }

    func decideNavigationPolicy(for response: WebPage.NavigationResponse) -> WKNavigationResponsePolicy {
        // 浏览器渲染不了的类型（zip、apk…）一律当作下载。
        guard !response.canShowMimeType else { return .allow }
        if let url = response.response.url {
            let request = URLRequest(url: url)
            Task { await self.download(request) }
        }
        return .cancel
    }

    /// 把下载落到「下载」目录，完成/失败都给 toast。
    /// （`WebPage` 没有暴露 WKDownloadDelegate 的目的地定制，这里用 URLSession 兜住。）
    func download(_ request: URLRequest) async {
        do {
            let (file, response) = try await URLSession.shared.download(for: request)
            let suggested = response.suggestedFilename ?? request.url?.lastPathComponent ?? "下载"
            let destination = Platform.uniqueFileURL(in: Platform.downloadsDirectory(), suggestedName: suggested)
            try FileManager.default.moveItem(at: file, to: destination)
            show(toast: "已保存到「下载」")
        } catch {
            show(toast: "下载失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 状态同步

    /// WebPage 的标题/进度/加载状态都是 `@Observable`：注册一轮跟踪，
    /// 任一变化就重新镜像并再次注册。
    private func trackPageObservation() {
        withObservationTracking {
            syncFromPage()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.trackPageObservation()
            }
        }
    }

    private func syncFromPage() {
        progress = page.estimatedProgress
        isLoading = page.isLoading
        if !page.title.isEmpty { title = page.title }
        currentURL = page.url
        canGoBack = !page.backForwardList.backList.isEmpty
        canGoForward = !page.backForwardList.forwardList.isEmpty
    }

    private func observeNavigations() async {
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    handleNavigationEvent(event)
                }
                return
            } catch {
                if handleNavigationError(error) { return }
                // 序列可能因错误终止，稍作退避后重建监听。
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func handleNavigationEvent(_ event: WebPage.NavigationEvent) {
        switch event {
        case .startedProvisionalNavigation:
            clearFailure()
        case .committed, .receivedServerRedirect:
            syncFromPage()
        case .finished:
            syncFromPage()
            clearFailure()
        @unknown default:
            break
        }
    }

    /// 返回 true 表示监听应当结束（页面已关闭）。
    private func handleNavigationError(_ error: any Error) -> Bool {
        guard let navigationError = error as? WebPage.NavigationError else {
            report(failure: LoadFailure(title: "页面加载失败", detail: error.localizedDescription, isOffline: false))
            return false
        }
        switch navigationError {
        case .failedProvisionalNavigation(let underlying):
            let described = failureDescription(for: underlying)
            guard !described.detail.isEmpty else { break }
            report(failure: described)
        case .invalidURL:
            report(failure: LoadFailure(title: "地址无效", detail: "", isOffline: false))
        case .webContentProcessTerminated:
            // WebContent 进程被系统回收（内存压力）。必须重载，否则白屏。
            report(failure: LoadFailure(
                title: "页面进程被系统回收",
                detail: "已为你重新加载。未保存的输入可能丢失。",
                isOffline: false
            ))
            page.reload()
        case .pageClosed:
            return true
        @unknown default:
            break
        }
        return false
    }

    // MARK: - 桥事件

    private func handleBridgeEvent(_ event: BridgeEvent) {
        switch event {
        case let .notify(title, body, rawURL, priority, tag):
            let resolved = resolve(rawURL)
            let createdAt = Date()
            let identifier: String = {
                if let tag, !tag.isEmpty { return "\(service.id)#web#\(tag)" }
                return NotificationItem.makeID(
                    serviceID: service.id,
                    eventID: nil,
                    title: title,
                    body: body,
                    createdAt: createdAt
                )
            }()
            let item = NotificationItem(
                id: identifier,
                serviceID: service.id,
                title: title,
                body: body,
                createdAt: createdAt,
                url: resolved ?? page.url,
                priority: priority,
                source: .web,
                receivedAt: createdAt
            )
            onNotification?(item)

        case let .open(rawURL):
            guard let url = resolve(rawURL) else { return }
            switch policy.decision(for: url, serviceHost: serviceHost) {
            case .allowInApp:
                load(url)
            case .openExternally:
                Platform.openExternally(url)
            case .cancel:
                break
            }

        case let .haptic(style):
            Platform.haptic(style)

        case let .log(message):
            onLog?("[\(service.id)] \(message)")

        case let .ready(title):
            if self.title.isEmpty, !title.isEmpty {
                self.title = title
            }
        }
    }

    private func resolve(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        guard let base = page.url ?? currentURL else { return nil }
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }

    // MARK: - 失败描述

    private func failureDescription(for error: any Error) -> LoadFailure {
        guard let urlError = error as? URLError else {
            return .init(title: "页面加载失败", detail: error.localizedDescription, isOffline: false)
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .init(
                title: "当前没有网络",
                detail: "「\(service.name)」的离线缓存会在恢复网络后自动更新，你也可以先重试。",
                isOffline: true
            )
        case .cannotFindHost, .dnsLookupFailed:
            return .init(
                title: "找不到「\(service.name)」",
                detail: "域名解析失败。请到「设置 → 接入方式」检查域名，或改用内网端口直连。",
                isOffline: false
            )
        case .cannotConnectToHost, .timedOut:
            return .init(
                title: "连接不上「\(service.name)」",
                detail: "服务可能没有启动，或当前网络访问不到该主机。",
                isOffline: false
            )
        case .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .secureConnectionFailed:
            return .init(
                title: "证书校验失败",
                detail: "自建服务使用的是系统不信任的证书。请给它配置受信任的 HTTPS（Service Worker 也需要 HTTPS 才能启用离线缓存）。",
                isOffline: false
            )
        case .appTransportSecurityRequiresSecureConnection:
            return .init(
                title: "被传输安全策略拦截",
                detail: "该地址需要 HTTPS。请改用域名访问，或在设置里配置受信任证书。",
                isOffline: false
            )
        case .cancelled:
            return .init(title: "已取消", detail: "", isOffline: false)
        default:
            return .init(
                title: "页面加载失败",
                detail: urlError.localizedDescription,
                isOffline: urlError.code == .notConnectedToInternet
            )
        }
    }

    private func report(failure: LoadFailure) {
        self.failure = failure
        self.isLoading = false
    }

    private func clearFailure() {
        failure = nil
    }

    private func show(toast message: String) {
        toast = message
    }
}

/// `WebPage.NavigationDeciding` 的实现：转发给 `WebAppModel`。
/// 独立小类是因为 WebPage 在 init 里就要拿到 decider，而那时 model 自己还没建好。
@MainActor
final class WebNavigationDecider: WebPage.NavigationDeciding {

    weak var model: WebAppModel?

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let model else { return .cancel }
        return model.decideNavigationPolicy(for: action)
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard let model else { return .cancel }
        return model.decideNavigationPolicy(for: response)
    }
}
