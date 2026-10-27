import Foundation

/// 一次导航是否留在内嵌 WebView 中。
public enum WebNavigationDecision: Equatable, Sendable {
    /// 留在 App 内的 WKWebView。
    case allowInApp
    /// 用系统浏览器 / SFSafariViewController 打开，避免破坏当前会话。
    case openExternally
    /// 丢弃（例如 `file://` 之外的未知协议）。
    case cancel
}

/// 内嵌浏览器的同源策略。
///
/// 目标：应用自身（含其子域与登录流程）留在 App 内，其余外链一律出栈，
/// 既保证登录、支付等流程可用，也避免用户"迷路"在别人的站点里回不来。
public struct WebContentPolicy: Sendable {

    /// 需要留在 App 内的第三方登录/授权域名。
    public var trustedHosts: Set<String>

    /// 站外的 http(s) 链接是否也留在应用内。
    ///
    /// 默认 `true`：点外链不再把人丢到 Safari，页面里就有「在浏览器打开」可以主动出去。
    /// `tel:` / `mailto:` 这类非网页协议始终交给系统，WebView 处理不了。
    public var keepsExternalLinksInApp: Bool

    public init(
        trustedHosts: Set<String> = WebContentPolicy.defaultTrustedHosts,
        keepsExternalLinksInApp: Bool = true
    ) {
        self.trustedHosts = trustedHosts
        self.keepsExternalLinksInApp = keepsExternalLinksInApp
    }

    public static let defaultTrustedHosts: Set<String> = [
        "appleid.apple.com",
        "accounts.google.com",
        "github.com",
        "login.microsoftonline.com"
    ]

    public func decision(for url: URL, serviceHost: String?) -> WebNavigationDecision {
        guard let scheme = url.scheme?.lowercased() else { return .cancel }

        switch scheme {
        case "http", "https":
            guard let host = url.host?.lowercased() else { return .cancel }
            if isSameSite(host: host, serviceHost: serviceHost) { return .allowInApp }
            if trustedHosts.contains(host) { return .allowInApp }
            if trustedHosts.contains(where: { host.hasSuffix("." + $0) }) { return .allowInApp }
            if keepsExternalLinksInApp { return .allowInApp }
            return .openExternally
        case "about", "blob", "data":
            return .allowInApp
        case "mailto", "tel", "sms", "itms-apps", "facetime":
            return .openExternally
        default:
            return .cancel
        }
    }

    /// 同站判断：主域相同或互为子域。
    public func isSameSite(host: String, serviceHost: String?) -> Bool {
        guard let serviceHost = serviceHost?.lowercased(), !serviceHost.isEmpty else { return false }
        if host == serviceHost { return true }
        return host.hasSuffix("." + serviceHost) || serviceHost.hasSuffix("." + host)
    }

    /// 是否给该页面注入原生桥（只注入自己的应用，避免污染第三方页面）。
    public func shouldInjectBridge(for url: URL, serviceHost: String?) -> Bool {
        guard let host = url.host else { return false }
        return isSameSite(host: host.lowercased(), serviceHost: serviceHost)
    }
}
