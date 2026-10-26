import Foundation
import WebKit
import ZhongmiaoCore

/// 页面内通知 / 原生能力桥的事件。
enum BridgeEvent: Sendable, Equatable {
    case notify(title: String, body: String, url: String?, priority: NotificationItem.Priority, tag: String?)
    case open(url: String)
    case haptic(style: String)
    case log(message: String)
    case ready(title: String)
}

/// 接收 `window.webkit.messageHandlers.zm` 的消息。
@MainActor
final class WebBridgeHandler: NSObject, WKScriptMessageHandler {

    var onEvent: ((BridgeEvent) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "zm", let payload = message.body as? [String: Any] else { return }
        guard let type = payload["type"] as? String else { return }

        switch type {
        case "notify":
            let title = (payload["title"] as? String) ?? ""
            let body = (payload["body"] as? String) ?? ""
            guard !(title.isEmpty && body.isEmpty) else { return }
            onEvent?(.notify(
                title: title.isEmpty ? "通知" : title,
                body: body,
                url: payload["url"] as? String,
                priority: BridgeEvent.parsePriority(payload["priority"] as? String),
                tag: payload["tag"] as? String
            ))
        case "open":
            if let url = payload["url"] as? String, !url.isEmpty {
                onEvent?(.open(url: url))
            }
        case "haptic":
            onEvent?(.haptic(style: (payload["style"] as? String) ?? "light"))
        case "log":
            onEvent?(.log(message: (payload["message"] as? String) ?? ""))
        case "ready":
            onEvent?(.ready(title: (payload["title"] as? String) ?? ""))
        default:
            break
        }
    }
}

extension BridgeEvent {
    static func parsePriority(_ raw: String?) -> NotificationItem.Priority {
        switch raw?.lowercased() {
        case "passive", "low": .passive
        case "time-sensitive", "timesensitive", "urgent", "high": .timeSensitive
        default: .active
        }
    }
}

/// `WebPage.Configuration` 配置工厂。
enum WebViewFactory {

    /// 注入脚本的版本号，随注入逻辑变更递增。
    static let scriptVersion = 4

    @MainActor
    static func makeConfiguration(service: ServiceDefinition, bridge: WebBridgeHandler) -> WebPage.Configuration {
        var configuration = WebPage.Configuration()

        // 持久化数据存储：Cookie、localStorage、Service Worker 缓存都跨启动保留。
        // 这是"离线可用"的前提——用 ephemeral 存储会让每次启动都回到空白状态。
        configuration.websiteDataStore = .default()
        // 让各应用能识别"这是众妙容器"，便于它们做布局或功能开关。
        configuration.applicationNameForUserAgent = "Zhongmiao/0.1"

        #if os(iOS)
        // 允许内联自动播放（等价于 allowsInlineMediaPlayback + 免用户手势）。
        configuration.mediaPlaybackBehavior = .allowsInlinePlayback
        #endif

        let controller = configuration.userContentController
        controller.add(bridge, name: "zm")

        // 页面级桥 + Notification 拦截：必须早于页面脚本执行。
        controller.addUserScript(
            WKUserScript(
                source: String(format: bridgeScript, scriptVersion),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        // DOM 就绪后补 viewport 与主题色，减少"桌面宽度"错位。
        controller.addUserScript(
            WKUserScript(
                source: layoutScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        return configuration
    }

    // MARK: - 注入脚本

    /// 1. 暴露 `window.__zhongmiao` 供页面主动调用；
    /// 2. 接管 `Notification` 与 `ServiceWorkerRegistration.showNotification`，
    ///    让页面里的通知真正落到系统通知中心（WKWebView 自身不提供该能力）。
    private static let bridgeScript = #"""
    (function () {
      if (window.__zhongmiaoBridgeInstalled) { return; }
      window.__zhongmiaoBridgeInstalled = true;

      var post = function (payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.zm) {
            window.webkit.messageHandlers.zm.postMessage(payload);
          }
        } catch (error) { /* 桥不可用时静默降级 */ }
      };

      var normalize = function (title, options) {
        options = options || {};
        var data = options.data || {};
        var url = '';
        if (data && typeof data.url === 'string') { url = data.url; }
        else if (typeof options.tag === 'string' && options.tag.indexOf('http') === 0) { url = options.tag; }
        return {
          type: 'notify',
          title: title === undefined || title === null ? '' : String(title),
          body: options.body === undefined || options.body === null ? '' : String(options.body),
          url: url,
          tag: options.tag ? String(options.tag) : '',
          priority: options.renotify ? 'timeSensitive' : 'active'
        };
      };

      function BridgedNotification(title, options) {
        post(normalize(title, options));
        options = options || {};
        this.title = title;
        this.body = options.body || '';
        this.icon = options.icon || '';
        this.tag = options.tag || '';
        this.data = options.data || null;
        this.close = function () {};
        this.addEventListener = function () {};
        this.removeEventListener = function () {};
        this.dispatchEvent = function () { return true; };
      }
      BridgedNotification.permission = 'granted';
      BridgedNotification.maxActions = 2;
      BridgedNotification.requestPermission = function (callback) {
        if (typeof callback === 'function') { callback('granted'); }
        return Promise.resolve('granted');
      };

      try {
        Object.defineProperty(window, 'Notification', {
          value: BridgedNotification, configurable: true, writable: true
        });
      } catch (error) { window.Notification = BridgedNotification; }

      try {
        if (window.ServiceWorkerRegistration && window.ServiceWorkerRegistration.prototype) {
          var originalShowNotification = window.ServiceWorkerRegistration.prototype.showNotification;
          window.__zhongmiaoOriginalShowNotification = originalShowNotification;
          window.ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
            post(normalize(title, options));
            return Promise.resolve();
          };
        }
      } catch (error) { /* 老系统忽略 */ }

      var originalOpen = window.open;
      window.open = function (url) {
        if (url) { post({ type: 'open', url: String(url) }); }
        return null;
      };
      window.__zhongmiaoOriginalOpen = originalOpen;

      window.__zhongmiao = {
        version: %d,
        notify: function (title, body, url) {
          post({
            type: 'notify',
            title: title == null ? '' : String(title),
            body: body == null ? '' : String(body),
            url: url ? String(url) : '',
            priority: 'active'
          });
        },
        open: function (url) { post({ type: 'open', url: String(url || '') }); },
        haptic: function (style) { post({ type: 'haptic', style: String(style || 'light') }); },
        log: function (message) { post({ type: 'log', message: String(message || '') }); },
        ready: function (title) { post({ type: 'ready', title: String(title || '') }); }
      };
    })();
    """#

    private static let layoutScript = #"""
    (function () {
      try {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.name = 'viewport';
          document.head.appendChild(meta);
        }
        var content = meta.getAttribute('content') || 'width=device-width, initial-scale=1';
        // 不用 viewport-fit=cover：cover 会让页面视口延伸到导航栏和状态栏下面，
        // 页面里 position: fixed 的顶栏（例如 ntfy 的汉堡菜单）会被系统导航栏压住、点不到。
        content = content.replace(/viewport-fit\s*=\s*[a-z-]+/i, 'viewport-fit=auto');
        if (content.indexOf('viewport-fit') === -1) {
          content += ', viewport-fit=auto';
        }
        if (content.indexOf('maximum-scale') === -1) {
          content += ', maximum-scale=5';
        }
        meta.setAttribute('content', content);
        document.documentElement.setAttribute('data-zhongmiao-container', 'ios');
      } catch (error) {}
    })();
    """#
}
