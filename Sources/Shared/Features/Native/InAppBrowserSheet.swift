import SwiftUI
import WebKit

/// 应用内的轻量浏览器。
///
/// 原生页里的站外链接（察新的 Release、ntfy 消息里的跳转等）如果用 SwiftUI 的 `Link`，
/// 系统一定交给 Safari；这里改成在 App 内用 WKWebView 打开，想出去再从右上角主动走浏览器。
struct InAppBrowserSheet: View {

    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                InAppWebView(url: url, isLoading: $isLoading)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                }
            }
            .navigationTitle(url.host ?? "网页")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Platform.openExternally(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("在浏览器打开")
                }
            }
        }
    }
}

/// 让 `URL` 能直接驱动 `.sheet(item:)`。
struct BrowserTarget: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

extension View {

    /// 统一的「点外链就地打开」出口：不再把用户丢到 Safari。
    func inAppBrowser(_ target: Binding<BrowserTarget?>) -> some View {
        sheet(item: target) { item in
            InAppBrowserSheet(url: item.url)
        }
    }
}

// MARK: - WKWebView

private struct InAppWebView {

    let url: URL
    @Binding var isLoading: Bool
}

#if os(iOS)
extension InAppWebView: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: InAppWebView

        init(_ parent: InAppWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            parent.isLoading = false
        }
    }
}
#elseif os(macOS)
extension InAppWebView: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url == nil else { return }
        webView.load(URLRequest(url: url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: InAppWebView

        init(_ parent: InAppWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            parent.isLoading = false
        }
    }
}
#endif
