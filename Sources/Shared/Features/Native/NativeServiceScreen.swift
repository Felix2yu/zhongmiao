import SwiftUI
import ZhongmiaoCore

/// 原生接入的页面壳。尚未实现原生界面的应用继续落到 WebView，避免功能回退。
struct NativeServiceScreen: View {

    @Environment(AppModel.self) private var model
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let service: ServiceDefinition

    var body: some View {
        Group {
            content
        }
        #if DEBUG
        // 调试预览会覆盖这一个服务的地址；标出来，避免被误当成「设置不生效」。
        .safeAreaInset(edge: .top, spacing: 0) {
            if let badge = IntegrationDebugSeed.previewBadge(for: service.id) {
                Text(badge)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.12))
            }
        }
        #endif
        #if os(iOS)
        // 与 ServiceScreen 一致：紧凑宽度下收起悬浮 Tab 栏，避免压住列表底部。
        .toolbar(horizontalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let url = model.url(for: service),
           let definition = IntegrationCatalog.definition(for: service.id) {
            switch service.id {
            case "qingye":
                QingyeScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "qiansi":
                QiansiScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "huozhi":
                HuozhiScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "mujian":
                MujianScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "diarum":
                DiarumScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "shenshi":
                ShenshiScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "qbhive":
                QbhiveScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "ntfy":
                NtfyScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "yuexi":
                YuexiScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "bili-history":
                BiliHistoryScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "chaxin":
                ChaxinScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            case "liuxia":
                LiuxiaScreen(
                    service: service,
                    baseURL: url,
                    definition: definition,
                    center: model.integrations
                )
            default:
                ServiceScreen(service: service, initialURL: url)
            }
        } else {
            ContentUnavailableView(
                "地址未配置",
                systemImage: "slash.circle",
                description: Text("「\(service.name)」缺少可用地址，请到设置里检查接入方式。")
            )
        }
    }
}
