import SwiftUI
import ZhongmiaoCore
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CatalogView: View {

    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var editingService: ServiceDefinition?

    private let columns = [
        GridItem(.adaptive(minimum: 158, maximum: 260), spacing: 12, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if allHidden && !isSearching {
                    ContentUnavailableView {
                        Label("所有应用都已隐藏", systemImage: "eye.slash")
                    } description: {
                        Text("到「设置 → 服务与接入」里取消隐藏，或在搜索框里直接搜应用名。")
                    }
                    .padding(.top, 32)
                } else if searchHasNoMatch {
                    ContentUnavailableView {
                        Label("没有匹配的应用", systemImage: "magnifyingglass")
                    } description: {
                        Text("换个关键词试试，隐藏的应用也能搜到。")
                    }
                    .padding(.top, 32)
                }

                ForEach(groups, id: \.category) { group in
                    let services = filtered(visible(group.services))
                    if !services.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(group.category.title, systemImage: group.category.symbol)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(services) { service in
                                    card(for: service)
                                }
                            }
                        }
                    }
                }

                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color.zmGrouped.ignoresSafeArea())
        .navigationTitle("众妙")
        .searchable(text: $searchText, prompt: "搜索应用")
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.network.isOnline {
                OfflineBanner(text: "当前离线，已缓存的应用仍可打开")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.syncNow(reason: "手动")
                } label: {
                    if model.isSyncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.isSyncing)
                .accessibilityLabel("同步所有应用的通知")
            }
        }
        .sheet(item: $editingService) { service in
            NavigationStack {
                ServiceConfigView(service: service, showsDoneButton: true)
            }
        }
    }

    /// 分组顺序来自注册表；组内置顶的排最前，同优先级保持注册表顺序。
    private var groups: [(category: ServiceDefinition.Category, services: [ServiceDefinition])] {
        ServiceCatalog.grouped { model.settings.preference(for: $0).isPinned ? 0 : 1 }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 全部隐藏时首页会只剩 footer，看起来像坏了，所以单独给一个空态。
    private var allHidden: Bool {
        !ServiceCatalog.all.contains { !model.settings.preference(for: $0).isHidden }
    }

    private var searchHasNoMatch: Bool {
        guard isSearching else { return false }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        return ServiceCatalog.all.allSatisfy { !matches($0, trimmed) }
    }

    /// 隐藏只作用于浏览态。搜索是明确意图，隐藏的服务照样能被搜到，
    /// 否则用户会以为服务丢了（卡片上会标「已隐藏」）。
    private func visible(_ services: [ServiceDefinition]) -> [ServiceDefinition] {
        isSearching ? services : services.filter { !model.settings.preference(for: $0).isHidden }
    }

    private func matches(_ service: ServiceDefinition, _ query: String) -> Bool {
        service.name.localizedStandardContains(query)
            || service.summary.localizedStandardContains(query)
            || service.id.localizedStandardContains(query)
    }

    private func filtered(_ services: [ServiceDefinition]) -> [ServiceDefinition] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return services }
        return services.filter { matches($0, trimmed) }
    }

    /// 卡片角标：ntfy 卡片要把独立订阅的主题也算进来。
    private func unreadCount(for service: ServiceDefinition) -> Int {
        model.snapshot.items.filter { item in
            guard !item.isRead else { return false }
            if item.serviceID == service.id { return true }
            return service.id == "ntfy" && NtfyTopic.isStandaloneServiceID(item.serviceID)
        }.count
    }

    private func card(for service: ServiceDefinition) -> some View {
        let resolved = model.url(for: service)
        let preference = model.settings.preference(for: service)
        return NavigationLink(value: AppModel.Route(serviceID: service.id)) {
            ServiceCard(
                service: service,
                unread: unreadCount(for: service),
                isConfigured: resolved != nil,
                isOfflineReady: service.kind.isOfflineCapable,
                showsCapabilityTag: model.settings.showServiceCapabilityTags,
                isHidden: preference.isHidden,
                isPinned: preference.isPinned
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
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
                editingService = service
            } label: {
                Label("服务设置", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("共 \(ServiceCatalog.all.count) 个服务 · \(ServiceCatalog.all.filter(\.kind.isOfflineCapable).count) 个离线可用")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("「离线可用」指该应用自带 Service Worker 缓存，断网也能打开，不代表服务当前的状态。全部应用经 Nginx 以 HTTPS 子域名提供，内网端口直连只用于排障。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }
}

struct ServiceCard: View {
    let service: ServiceDefinition
    let unread: Int
    let isConfigured: Bool
    let isOfflineReady: Bool
    /// 是否显示离线能力标签（设置里的开关）。
    var showsCapabilityTag = true
    /// 该服务已被设为「在首页隐藏」。只有搜索时卡片才会出现在首页，这里标出来。
    var isHidden = false
    /// 该服务已置顶。位置变化之外再给一个视觉锚点，否则跨会话就认不出哪些被置顶了。
    var isPinned = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ServiceGlyph(service: service, size: 40)
                Spacer(minLength: 0)
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("已置顶")
                }
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red, in: Capsule())
                        .accessibilityLabel("\(unread) 条未读")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(service.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 4) {
                if isHidden {
                    CapsuleTag(text: "已隐藏", systemImage: "eye.slash")
                }
                if showsCapabilityTag && isOfflineReady {
                    CapsuleTag(
                        text: "离线可用",
                        systemImage: "arrow.down.to.line",
                        tint: .green
                    )
                }
                if !isConfigured {
                    CapsuleTag(text: "未配置", systemImage: "exclamationmark", tint: .orange)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
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
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(service.accessibilityDescription)
        .accessibilityHint("打开 \(service.name)")
        .accessibilityValue(unread > 0 ? "\(unread) 条未读" : "")
    }
}

enum Pasteboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
