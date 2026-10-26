import SwiftUI
import WebKit
import ZhongmiaoCore

/// 承载 `WebAppModel` 的 `WebPage`。
/// iOS 26 起 SwiftUI 原生提供 `WebView`，不再需要 Representable 桥接。
struct WebViewHost: View {

    let model: WebAppModel

    var body: some View {
        #if os(iOS)
        WebView(model.page)
            .refreshable {
                await model.pullToRefresh()
            }
        #else
        WebView(model.page)
        #endif
    }
}
