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
                ForEach(ServiceCatalog.grouped, id: \.category) { group in
                    let services = filtered(group.services)
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
                ServiceEditorView(service: service)
            }
        }
    }

    private func filtered(_ services: [ServiceDefinition]) -> [ServiceDefinition] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return services }
        return services.filter {
            $0.name.localizedStandardContains(trimmed)
                || $0.summary.localizedStandardContains(trimmed)
                || $0.id.localizedStandardContains(trimmed)
        }
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
        return NavigationLink(value: AppModel.Route(serviceID: service.id)) {
            ServiceCard(
                service: service,
                unread: unreadCount(for: service),
                isConfigured: resolved != nil,
                isOfflineReady: service.kind.isOfflineCapable,
                showsCapabilityTag: model.settings.showServiceCapabilityTags
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ServiceGlyph(service: service, size: 40)
                Spacer(minLength: 0)
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
