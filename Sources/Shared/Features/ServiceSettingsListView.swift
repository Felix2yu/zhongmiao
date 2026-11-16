import SwiftUI
import ZhongmiaoCore

/// 服务与接入的唯一入口。
///
/// 之前有两个平行列表：按应用分类的「服务 → 逐服务配置」和按 P0/P1/P2 的「应用接入」，
/// 指向同一批 14 个应用，等于同一件事有两套门牌号。现在只保留这一个，
/// 分组沿用首页的分类，登录状态与地址覆盖都收进单服务页。
struct ServiceSettingsListView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        #if os(macOS)
        macBody
        #else
        iosBody
        #endif
    }

    // MARK: - iOS

    #if os(iOS)
    private var iosBody: some View {
        List {
            summarySection

            ForEach(groups, id: \.category) { group in
                Section(group.category.title) {
                    ForEach(group.services) { service in
                        NavigationLink {
                            ServiceConfigView(service: service)
                        } label: {
                            row(for: service)
                        }
                    }
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("被设为「在首页隐藏」的应用仍在这里（带划掉的眼睛标记），点进去取消隐藏即可恢复。所有改动写入本机设置，凭据写入系统钥匙串。")
            }
        }
        .navigationTitle("服务与接入")
        .task { await model.integrations.refreshReminderCounts() }
    }
    #endif

    // MARK: - macOS

    #if os(macOS)
    /// 与设置页同一套分组卡片。`Form` 在 macOS 上是两列布局、没有卡片背景，
    /// 整页会退化成裸文本堆叠，所以这里也自绘。
    private var macBody: some View {
        MacSettingsPage {
            MacSettingsGroup(title: "概览", footer: summaryFooter) {
                MacSettingsRow(title: "可解析地址") {
                    Text("\(configuredCount)/\(ServiceCatalog.all.count)")
                        .foregroundStyle(.secondary)
                }

                MacSettingsDivider()

                MacSettingsRow(title: "原生接入") {
                    Text("\(connectedCount)/\(integratedCount) 已连接")
                        .foregroundStyle(connectedCount < integratedCount ? Color.secondary : Color.primary)
                }
            }

            ForEach(groups, id: \.category) { group in
                MacSettingsGroup(title: group.category.title) {
                    ForEach(Array(group.services.enumerated()), id: \.element.id) { index, service in
                        MacServiceLinkRow(service: service)

                        if index < group.services.count - 1 {
                            MacSettingsDivider()
                        }
                    }
                }
            }
        }
        .navigationTitle("服务与接入")
        .navigationDestination(for: MacServiceRoute.self) { route in
            if let service = ServiceCatalog.service(id: route.id) {
                ServiceConfigView(service: service)
            }
        }
        .task { await model.integrations.refreshReminderCounts() }
    }

    private var summaryFooter: String {
        "「可解析地址」统计能算出 URL 的服务；「原生接入」统计凭据可用、无需网页版的 P0/P1/P2 应用。全局域名与主机在「设置 → 接入方式」里，这里只管单个服务的覆盖值。被设为「在首页隐藏」的应用仍在这里（带划掉的眼睛标记），点进去取消隐藏即可恢复。"
    }
    #endif

    // MARK: - 概览

    private var summarySection: some View {
        Section {
            LabeledContent("可解析地址", value: "\(configuredCount)/\(ServiceCatalog.all.count)")
            LabeledContent("原生接入") {
                Text("\(connectedCount)/\(integratedCount) 已连接")
                    .foregroundStyle(connectedCount < integratedCount ? Color.secondary : Color.primary)
            }
        } header: {
            Text("概览")
        } footer: {
            Text("「可解析地址」统计能算出 URL 的服务；「原生接入」统计凭据可用、无需网页版的 P0/P1/P2 应用。全局域名与主机在「设置 → 接入方式」里，这里只管单个服务的覆盖值。")
        }
    }

    private var groups: [(category: ServiceDefinition.Category, services: [ServiceDefinition])] {
        ServiceCatalog.grouped { model.settings.preference(for: $0).isPinned ? 0 : 1 }
    }

    private var configuredCount: Int {
        ServiceCatalog.all.filter { model.url(for: $0) != nil }.count
    }

    private var integratedCount: Int {
        IntegrationCatalog.integrated.count
    }

    private var connectedCount: Int {
        IntegrationCatalog.integrated.filter { model.integrations.state(for: $0.serviceID).isUsable }.count
    }

    // MARK: - 行

    private func row(for service: ServiceDefinition) -> some View {
        let resolved = model.url(for: service)
        let preference = model.settings.preference(for: service)
        let definition = IntegrationCatalog.definition(for: service.id)
        let state = model.integrations.state(for: service.id)

        return HStack(spacing: 10) {
            ServiceGlyph(service: service, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(service.name)
                        .zmFont(.subheadline)
                    if preference.isPinned {
                        Image(systemName: "pin.fill")
                            .zmFont(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("已置顶")
                    }
                    if preference.isHidden {
                        Image(systemName: "eye.slash")
                            .zmFont(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("首页已隐藏")
                    }
                    if preference.notificationsEnabled {
                        Image(systemName: "bell.fill")
                            .zmFont(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("参与通知同步")
                    }
                }
                Text(resolved?.absoluteString ?? "未配置地址")
                    .zmFont(.caption2, design: .monospaced)
                    .foregroundStyle(resolved == nil ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(definition?.priority.shortTitle ?? "—")
                    .zmFont(.caption2, design: .monospaced)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.tint)
                        .frame(width: 6, height: 6)
                    Text(state.title)
                        .zmFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

#if os(macOS)
/// 服务列表里的一行：图标 + 名称/地址 + 优先级/连接状态 + 箭头，整行可点进单服务配置页。
private struct MacServiceLinkRow: View {

    let service: ServiceDefinition

    @Environment(AppModel.self) private var model
    @Environment(\.interfaceScale) private var scale
    @State private var hovering = false

    private var resolved: URL? { model.url(for: service) }
    private var preference: ServicePreference { model.settings.preference(for: service) }
    private var definition: IntegrationDefinition? { IntegrationCatalog.definition(for: service.id) }
    private var state: IntegrationCenter.CredentialState { model.integrations.state(for: service.id) }

    var body: some View {
        NavigationLink(value: MacServiceRoute(id: service.id)) {
            HStack(spacing: 10.zmScaled(scale)) {
                ServiceGlyph(service: service, size: 26.zmScaled(scale))

                VStack(alignment: .leading, spacing: 2.zmScaled(scale)) {
                    HStack(spacing: 5.zmScaled(scale)) {
                        Text(service.name)
                            .zmFont(.subheadline)
                            .lineLimit(1)
                        if preference.isPinned {
                            Image(systemName: "pin.fill")
                                .zmFont(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        if preference.isHidden {
                            Image(systemName: "eye.slash")
                                .zmFont(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        if preference.notificationsEnabled {
                            Image(systemName: "bell.fill")
                                .zmFont(.caption2)
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(resolved?.absoluteString ?? "未配置地址")
                        .zmFont(.caption2, design: .monospaced)
                        .foregroundStyle(resolved == nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2.zmScaled(scale)) {
                    Text(definition?.priority.shortTitle ?? "—")
                        .zmFont(.caption2, design: .monospaced)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4.zmScaled(scale)) {
                        Circle()
                            .fill(state.tint)
                            .frame(width: 6, height: 6)
                        Text(state.title)
                            .zmFont(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .zmFont(size: 10, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 6.zmScaled(scale))
            .frame(minHeight: 44.zmScaled(scale))
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(service.name)，\(state.title)"))
        .onHover { hovering = $0 }
    }
}

/// 服务列表的导航值。用独立类型而不是裸 `String`，免得和别的 `String` 目的地撞上。
struct MacServiceRoute: Hashable {
    let id: String
}
#endif
