#if os(macOS)
import SwiftUI
import ZhongmiaoCore

/// macOS 首页：分类横向分栏 + 44pt 行条目。
///
/// 规格见 `docs/DESIGN-macOS.md` 3.1。与 iOS 的差别只有两处：分类按栏流动
/// （栏内纵向、栏间横向），入口从 132pt 竖卡降为 44pt 横条。卡片语言没变——
/// 16 圆角 + `zmCard` 底 + 0.5pt 描边 + 阴影从「每个入口一张」上移到「每个分类一张」。
struct CatalogBoard: View {

    typealias Group = (category: ServiceDefinition.Category, services: [ServiceDefinition])

    let groups: [Group]
    var onConfigure: (ServiceDefinition) -> Void

    @State private var width: CGFloat = 0
    /// 栏间距与断点都随界面缩放走：字大了，一行能放的列自然少了。
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 18.zmScaled(scale)) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 18.zmScaled(scale)) {
                    ForEach(column, id: \.category) { group in
                        CategoryCard(
                            category: group.category,
                            services: group.services,
                            onConfigure: onConfigure
                        )
                    }
                }
                // 栏宽由内容平分，各栏独立向下堆叠，不强行等高。
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
    }

    private var columns: [[Group]] {
        Self.distribute(groups, into: columnCount)
    }

    /// 栏数由栏宽下限反推，与窗口总宽无关：行里要同时放下 Glyph、名称、摘要与状态，
    /// 栏宽低于 300 时摘要只剩四五个字。300 随界面缩放走，放大后自然退到更少的栏。
    private var columnCount: Int {
        if width >= 940.zmScaled(scale) { return 3 }
        if width >= 620.zmScaled(scale) { return 2 }
        return 1
    }

    /// 顺序装箱：按注册表顺序依次放入当前栏，累计高度超过「总高 ÷ 栏数 × 1.2」时换下一栏。
    ///
    /// 分类数与每类条目数都由注册表决定，这里用 `50 + 44N` 估算高度（50 = 卡片上下内距
    /// 12×2 + 标题 18 + 标题下距 8），不做运行时测量；注册表增删分类时不需要改表。
    static func distribute(_ groups: [Group], into count: Int) -> [[Group]] {
        guard count > 1, groups.count > 1 else { return [groups] }
        let heights = groups.map { 50 + 44 * $0.services.count }
        let target = Double(heights.reduce(0, +)) / Double(count) * 1.2

        var result: [[Group]] = []
        var bucket: [Group] = []
        var accumulated = 0

        for (index, group) in groups.enumerated() {
            let height = heights[index]
            let remaining = groups.count - index
            let columnsLeft = count - result.count
            // 换栏的两个条件：超出目标高度，且剩余的组还够后面每栏至少分到一个。
            if !bucket.isEmpty,
               Double(accumulated + height) > target,
               result.count < count - 1,
               remaining >= columnsLeft {
                result.append(bucket)
                bucket = []
                accumulated = 0
            }
            bucket.append(group)
            accumulated += height
        }
        result.append(bucket)
        return result
    }
}

/// 一张分类卡：标题行 + 若干服务行。
private struct CategoryCard: View {

    let category: ServiceDefinition.Category
    let services: [ServiceDefinition]
    var onConfigure: (ServiceDefinition) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 8.zmScaled(scale)) {
            Label(category.title, systemImage: category.symbol)
                .zmFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(height: 18.zmScaled(scale), alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                    ServiceRow(
                        service: service,
                        isLast: index == services.count - 1,
                        onConfigure: onConfigure
                    )
                }
            }
        }
        .padding(12.zmScaled(scale))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.zmCard)
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0 : 0.04),
                    radius: 6,
                    y: 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }
}

/// 一条服务入口：`[Glyph 28] 名称 · 摘要 ………… [状态]`。
private struct ServiceRow: View {

    let service: ServiceDefinition
    let isLast: Bool
    var onConfigure: (ServiceDefinition) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.interfaceScale) private var scale
    @State private var isHovering = false

    var body: some View {
        NavigationLink(value: AppModel.Route(serviceID: service.id)) {
            HStack(spacing: 8.zmScaled(scale)) {
                ServiceGlyph(service: service, size: 28)

                Text(service.name)
                    .zmFont(size: 13, weight: .semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    // 名称定宽：否则摘要起点跟着名字长短浮动，每行都要重新找起点。
                    .frame(minWidth: 72.zmScaled(scale), alignment: .leading)

                Text(service.summary)
                    .zmFont(size: 11.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                status
            }
            .padding(.horizontal, 8.zmScaled(scale))
            .frame(height: 44.zmScaled(scale))
            .background(
                hoverColor,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(capabilityNote)
        .contextMenu { menu }
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(.separator.opacity(0.35))
                    .frame(height: 0.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(service.accessibilityDescription)
        .accessibilityHint("打开 \(service.name)")
        .accessibilityValue(statusDescription)
    }

    private var preference: ServicePreference {
        model.settings.preference(for: service)
    }

    private var resolved: URL? {
        model.url(for: service)
    }

    /// 只做「可点击的确认」，不做形变——文字在非整数倍缩放下会发虚。
    private var hoverColor: Color {
        guard isHovering else { return .clear }
        return .primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
    }

    /// 能力标签退出行内后的落点：指针停留时由系统气泡给出。
    private var capabilityNote: String {
        let capability = service.kind.offlineCapabilityDescription
        let detail = service.kind.isOfflineCapable ? "断网也能打开" : "需要网络"
        return "\(service.name)：\(service.summary)\n\(capability) · \(detail)"
    }

    /// 右键菜单里的同一份说明，压成一行。
    private var capabilityMenuNote: String {
        service.kind.isOfflineCapable
            ? "离线可用 · Service Worker 缓存"
            : "需要联网 · 无离线缓存"
    }

    /// 状态槽只放信号，不放能力（能力是恒定属性，14 个入口里 12 个同款，没有区分度）。
    /// 唯一例外是用户在设置或「显示」菜单里主动打开能力标签——那时按原样挂回来。
    @ViewBuilder
    private var status: some View {
        HStack(spacing: 6) {
            if preference.isHidden {
                CapsuleTag(text: "已隐藏", systemImage: "eye.slash")
            }
            if model.settings.showServiceCapabilityTags && service.kind.isOfflineCapable {
                CapsuleTag(text: "离线可用", systemImage: "arrow.down.to.line", tint: .green)
            }
            if resolved == nil {
                CapsuleTag(text: "未配置", systemImage: "exclamationmark", tint: .orange)
            }
            if unread > 0 {
                Text("\(unread)")
                    .zmFont(.caption2, weight: .bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
            }
        }
    }

    private var statusDescription: String {
        var parts: [String] = []
        if unread > 0 { parts.append("\(unread) 条未读") }
        if preference.isHidden { parts.append("已隐藏") }
        if resolved == nil { parts.append("未配置地址") }
        return parts.joined(separator: "，")
    }

    /// ntfy 卡片要把独立订阅的主题也算进来，与 iOS 卡片口径一致。
    private var unread: Int {
        model.snapshot.items.filter { item in
            guard !item.isRead else { return false }
            if item.serviceID == service.id { return true }
            return service.id == "ntfy" && NtfyTopic.isStandaloneServiceID(item.serviceID)
        }.count
    }

    @ViewBuilder
    private var menu: some View {
        // 从行内撤下的能力说明，在右键菜单顶部以只读行承接（单行，避免菜单项被折行）。
        Text(capabilityMenuNote)

        Divider()

        if IntegrationCatalog.definition(for: service.id) != nil {
            Button {
                model.pendingRoute = AppModel.Route(serviceID: service.id)
            } label: {
                Label("打开原生页", systemImage: "macwindow")
            }

            Button {
                model.pendingRoute = AppModel.Route(serviceID: service.id, preferWeb: true)
            } label: {
                Label("打开网页版", systemImage: "globe")
            }

            Divider()
        }

        Button {
            if let resolved { Platform.openExternally(resolved) }
        } label: {
            Label("在浏览器打开", systemImage: "safari")
        }
        .disabled(resolved == nil)

        Button {
            if let resolved {
                Pasteboard.copy(resolved.absoluteString)
                model.toast = "地址已复制"
            }
        } label: {
            Label("复制地址", systemImage: "doc.on.doc")
        }
        .disabled(resolved == nil)

        Button {
            model.probe(service)
            model.toast = "正在检测 \(service.name)"
        } label: {
            Label("检测连通性", systemImage: "waveform.path.ecg")
        }

        Divider()

        Button {
            let willPin = !preference.isPinned
            model.setPinned(willPin, for: service.id)
            model.toast = willPin ? "已置顶 \(service.name)" : "已取消置顶 \(service.name)"
        } label: {
            Label(
                preference.isPinned ? "取消置顶" : "置顶",
                systemImage: preference.isPinned ? "pin.slash" : "pin"
            )
        }

        Button {
            model.setHidden(true, for: service.id)
            model.toast = "已隐藏 \(service.name)，可在「设置 → 服务」恢复"
        } label: {
            Label("在首页隐藏", systemImage: "eye.slash")
        }

        Divider()

        Button {
            onConfigure(service)
        } label: {
            Label("服务设置", systemImage: "slider.horizontal.3")
        }
    }
}

/// 搜索结果用单栏行列表：命中通常只有几条，再分栏会把相关性割裂到不同列。
struct CatalogSearchResults: View {

    let services: [ServiceDefinition]
    var onConfigure: (ServiceDefinition) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.interfaceScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                ServiceRow(
                    service: service,
                    isLast: index == services.count - 1,
                    onConfigure: onConfigure
                )
            }
        }
        .padding(12.zmScaled(scale))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.zmCard)
                .shadow(
                    color: .black.opacity(colorScheme == .dark ? 0 : 0.04),
                    radius: 6,
                    y: 2
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 0.5)
        }
    }
}
#endif
