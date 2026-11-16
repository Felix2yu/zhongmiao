import SwiftUI
import ZhongmiaoCore

/// 诊断页：连通性、原生接入、离线说明、运行状态与日志。
///
/// iOS 用 `List`；macOS 与设置页共用同一套分组卡片——`List` 在 macOS 上会铺满整窗、
/// 行直接贴边，和设置页的卡片是两种语言。
struct DiagnosticsView: View {

    @Environment(AppModel.self) private var model
    @State private var editingService: ServiceDefinition?

    var body: some View {
        content
            .navigationTitle("诊断")
            .task { await model.integrations.refreshReminderCounts() }
            .sheet(item: $editingService) { service in
                NavigationStack {
                    ServiceConfigView(service: service, showsDoneButton: true)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.probeAll()
                    } label: {
                        if model.isProbing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("全部检测")
                        }
                    }
                    .disabled(model.isProbing)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macBody
        #else
        List {
            Section {
                ForEach(ServiceCatalog.all) { service in
                    row(for: service)
                }
            } header: {
                Text("服务连通性")
            } footer: {
                Text(connectivityFooter)
            }

            Section {
                ForEach(IntegrationCatalog.integrated) { definition in
                    if let service = ServiceCatalog.service(id: definition.serviceID) {
                        NavigationLink {
                            ServiceConfigView(service: service)
                        } label: {
                            integrationRow(definition: definition, service: service)
                        }
                    }
                }
            } header: {
                Text("原生接入")
            } footer: {
                Text(integrationFooter)
            }

            Section("为什么离线有时不生效") {
                bullet(
                    "你的部署是 Nginx + HTTPS，Service Worker 可以正常注册，离线缓存生效。只有临时改成 http://IP:端口 排障时才会失去离线能力。",
                    symbol: "lock.shield"
                )
                bullet(
                    "各应用的离线能力来自它们自己的 sw.js。缓存过期或被清除后，首次打开仍需联网。",
                    symbol: "externaldrive.badge.questionmark"
                )
                bullet(
                    "通知依赖各自的通知流或 ntfy 主题。没有配置通道的服务只会转发页面内的提醒。",
                    symbol: "bell.slash"
                )
            }

            Section {
                LabeledContent("网络", value: model.network.summary)
                LabeledContent("通知授权", value: model.notificationStatusText)
                LabeledContent("收件箱", value: "\(model.snapshot.items.count) 条 · 未读 \(model.snapshot.unreadCount)")
                LabeledContent("待补发", value: "\(model.snapshot.pendingCount) 条")
                if let last = model.snapshot.lastSyncAt {
                    LabeledContent("上次同步", value: RelativeTime.short(last))
                }
            } header: {
                Text("运行状态")
            }

            Section {
                logRows

                if !model.log.isEmpty {
                    Button("清空日志", role: .destructive) {
                        model.clearLog()
                    }
                }
            } header: {
                Text("运行日志")
            } footer: {
                Text(logFooter)
            }
        }
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    @Environment(\.interfaceScale) private var scale

    private var macBody: some View {
        MacSettingsPage {
            MacSettingsGroup(title: "服务连通性", footer: connectivityFooter) {
                let services = ServiceCatalog.all
                ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                    macServiceRow(service)
                    if index < services.count - 1 {
                        MacSettingsDivider()
                    }
                }
            }

            MacSettingsGroup(title: "原生接入", footer: integrationFooter) {
                let definitions = IntegrationCatalog.integrated
                ForEach(Array(definitions.enumerated()), id: \.element.id) { index, definition in
                    if let service = ServiceCatalog.service(id: definition.serviceID) {
                        macIntegrationRow(definition: definition, service: service)
                        if index < definitions.count - 1 {
                            MacSettingsDivider()
                        }
                    }
                }
            }

            MacSettingsGroup(title: "为什么离线有时不生效") {
                MacSettingsStackRow {
                    Label {
                        Text("你的部署是 Nginx + HTTPS，Service Worker 可以正常注册，离线缓存生效。只有临时改成 http://IP:端口 排障时才会失去离线能力。")
                            .zmFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.tertiary)
                    }
                }

                MacSettingsDivider()

                MacSettingsStackRow {
                    Label {
                        Text("各应用的离线能力来自它们自己的 sw.js。缓存过期或被清除后，首次打开仍需联网。")
                            .zmFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .foregroundStyle(.tertiary)
                    }
                }

                MacSettingsDivider()

                MacSettingsStackRow {
                    Label {
                        Text("通知依赖各自的通知流或 ntfy 主题。没有配置通道的服务只会转发页面内的提醒。")
                            .zmFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            MacSettingsGroup(title: "运行状态") {
                MacSettingsRow(title: "网络") {
                    Text(model.network.summary)
                        .foregroundStyle(.secondary)
                }

                MacSettingsDivider()

                MacSettingsRow(title: "通知授权") {
                    Text(model.notificationStatusText)
                        .foregroundStyle(.secondary)
                }

                MacSettingsDivider()

                MacSettingsRow(title: "收件箱") {
                    Text("\(model.snapshot.items.count) 条 · 未读 \(model.snapshot.unreadCount)")
                        .foregroundStyle(.secondary)
                }

                MacSettingsDivider()

                MacSettingsRow(title: "待补发") {
                    Text("\(model.snapshot.pendingCount) 条")
                        .foregroundStyle(.secondary)
                }

                if let last = model.snapshot.lastSyncAt {
                    MacSettingsDivider()

                    MacSettingsRow(title: "上次同步") {
                        Text(RelativeTime.short(last))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MacSettingsGroup(title: "运行日志", footer: logFooter) {
                if model.log.isEmpty {
                    MacSettingsStackRow {
                        Text("暂无日志")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in
                        MacSettingsStackRow {
                            Text(line)
                                .zmFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        if index < model.log.count - 1 {
                            MacSettingsDivider()
                        }
                    }

                    MacSettingsDivider()

                    MacSettingsButtonRow(title: "清空日志", systemImage: "trash", role: .destructive) {
                        model.clearLog()
                    }
                }
            }
        }
    }

    private func macServiceRow(_ service: ServiceDefinition) -> some View {
        let health = model.health(for: service)
        let url = model.url(for: service)

        return MacSettingsStackRow {
            HStack(spacing: 10.zmScaled(scale)) {
                ServiceGlyph(service: service, size: 28.zmScaled(scale))

                VStack(alignment: .leading, spacing: 2.zmScaled(scale)) {
                    Text(service.name)
                        .zmFont(.subheadline, weight: .medium)
                    Text(url?.absoluteString ?? "未配置地址")
                        .zmFont(.caption2, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Image(systemName: health.symbol)
                        .zmFont(.caption2)
                        .foregroundStyle(health.isUsable ? Color.green : Color.secondary)
                    Text(health.title)
                        .zmFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Menu {
                    Button {
                        model.probe(service)
                    } label: {
                        Label("检测", systemImage: "waveform.path.ecg")
                    }
                    Button {
                        if let url {
                            Pasteboard.copy(url.absoluteString)
                            model.toast = "地址已复制"
                        }
                    } label: {
                        Label("复制地址", systemImage: "doc.on.doc")
                    }
                    .disabled(url == nil)
                    Button {
                        if let url { Platform.openExternally(url) }
                    } label: {
                        Label("在浏览器打开", systemImage: "safari")
                    }
                    .disabled(url == nil)
                    Button {
                        editingService = service
                    } label: {
                        Label("服务设置", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .zmFont(.footnote)
                        .frame(width: 26.zmScaled(scale), height: 20.zmScaled(scale))
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("\(service.name) 的操作")
            }
        }
    }

    private func macIntegrationRow(definition: IntegrationDefinition, service: ServiceDefinition) -> some View {
        MacIntegrationLinkRow(definition: definition, service: service)
    }
    #endif

    // MARK: - 文案

    private var connectivityFooter: String {
        "诊断会向每个服务的首页发一次 GET 请求。返回 401/403 视为「可达但需要登录」，这对自建应用是正常状态。地址不对时点行尾的「…」直接进该服务的配置页改，不用回设置里翻。"
    }

    private var integrationFooter: String {
        "凭据只在系统钥匙串与本机内存中，日志不记录令牌。提醒数量是当前已排程的本地通知。点进任一应用可直接改它的凭据与提醒。"
    }

    private var logFooter: String {
        "日志只保存在本机内存中，重启后清空。"
    }

    @ViewBuilder
    private var logRows: some View {
        if model.log.isEmpty {
            Text("暂无日志").foregroundStyle(.secondary)
        } else {
            ForEach(model.log, id: \.self) { line in
                Text(line)
                    .zmFont(.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func row(for service: ServiceDefinition) -> some View {
        let health = model.health(for: service)
        let url = model.url(for: service)

        HStack(alignment: .top, spacing: 10) {
            ServiceGlyph(service: service, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .zmFont(.subheadline, weight: .medium)
                Text(url?.absoluteString ?? "未配置地址")
                    .zmFont(.caption2, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: health.symbol)
                        .zmFont(.caption2)
                        .foregroundStyle(health.isUsable ? .green : .secondary)
                    Text(health.title)
                        .zmFont(.caption2)
                        .foregroundStyle(health.isUsable ? .secondary : .secondary)
                }
            }

            Spacer(minLength: 4)

            Menu {
                Button {
                    model.probe(service)
                } label: {
                    Label("检测", systemImage: "waveform.path.ecg")
                }
                Button {
                    if let url {
                        Pasteboard.copy(url.absoluteString)
                        model.toast = "地址已复制"
                    }
                } label: {
                    Label("复制地址", systemImage: "doc.on.doc")
                }
                .disabled(url == nil)
                Button {
                    if let url { Platform.openExternally(url) }
                } label: {
                    Label("在浏览器打开", systemImage: "safari")
                }
                .disabled(url == nil)
                Button {
                    editingService = service
                } label: {
                    Label("服务设置", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .zmFont(.footnote)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(service.name) 的操作")
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func integrationRow(definition: IntegrationDefinition, service: ServiceDefinition) -> some View {
        let state = model.integrations.state(for: definition.serviceID)
        HStack(spacing: 10) {
            ServiceGlyph(service: service, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .zmFont(.subheadline)
                Text(definition.priority.shortTitle + " · " + definition.authKind.title)
                    .zmFont(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle().fill(state.tint).frame(width: 6, height: 6)
                    Text(state.title)
                        .zmFont(.caption2)
                        .foregroundStyle(.secondary)
                }
                if definition.supportsReminders {
                    Text("提醒 \(model.integrations.reminderCounts[definition.serviceID] ?? 0) 条")
                        .zmFont(.caption2, monospacedDigit: true)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func bullet(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .zmFont(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

#if os(macOS)
/// 原生接入分组的行：应用图标 + 名称/优先级 + 连接状态 + 提醒数 + 箭头，整行可点。
private struct MacIntegrationLinkRow: View {

    let definition: IntegrationDefinition
    let service: ServiceDefinition

    @Environment(AppModel.self) private var model
    @Environment(\.interfaceScale) private var scale
    @State private var hovering = false

    private var state: IntegrationCenter.CredentialState {
        model.integrations.state(for: definition.serviceID)
    }

    var body: some View {
        NavigationLink {
            ServiceConfigView(service: service)
        } label: {
            HStack(spacing: 10.zmScaled(scale)) {
                ServiceGlyph(service: service, size: 24.zmScaled(scale))

                VStack(alignment: .leading, spacing: 2.zmScaled(scale)) {
                    Text(service.name)
                        .zmFont(.subheadline)
                    Text("\(definition.priority.shortTitle) · \(definition.authKind.title)")
                        .zmFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if definition.supportsReminders {
                    Text("提醒 \(model.integrations.reminderCounts[definition.serviceID] ?? 0) 条")
                        .zmFont(.caption2, monospacedDigit: true)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4.zmScaled(scale)) {
                    Circle()
                        .fill(state.tint)
                        .frame(width: 6, height: 6)
                    Text(state.title)
                        .zmFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .zmFont(size: 10, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14.zmScaled(scale))
            .padding(.vertical, 6.zmScaled(scale))
            .frame(minHeight: 40.zmScaled(scale))
            .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(service.name)，\(state.title)"))
        .onHover { hovering = $0 }
    }
}
#endif
