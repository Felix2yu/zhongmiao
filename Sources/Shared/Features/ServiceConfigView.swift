import SwiftUI
import ZhongmiaoCore

/// 单个服务的全部配置：地址、鉴权、通知通道、提醒、首页显示、诊断。
///
/// 存在的理由：这些维度原本散在三处——「设置 → 接入方式」（全局域名）、
/// 「设置 → 应用接入」（凭据与提醒）、「设置 → 服务 → 逐服务配置」（地址覆盖与通知流）。
/// 同一个服务的地址和凭据要跨三个页面来回跳，还出现同一份令牌的两个入口。
/// 现在一个服务一页，页内分区即配置的完整维度，用户不需要知道配置原属于哪个系统。
struct ServiceConfigView: View {

    let service: ServiceDefinition
    /// 从 sheet 打开时需要显式「完成」；push 进栈时用系统返回即可。
    var showsDoneButton = false

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var showCredential = false
    @State private var showClearCredentialConfirm = false
    @State private var isValidating = false

    private var definition: IntegrationDefinition? {
        IntegrationCatalog.definition(for: service.id)
    }

    private var resolvedURL: URL? {
        model.url(for: service)
    }

    private var credentialState: IntegrationCenter.CredentialState {
        model.integrations.state(for: service.id)
    }

    private var integrationPreference: IntegrationPreference {
        model.integrations.preference(for: service.id)
    }

    private var servicePreference: ServicePreference {
        model.settings.preference(for: service)
    }

    private var health: ServiceHealth {
        model.health(for: service)
    }

    private var hasStoredCredential: Bool {
        !(model.integrations.credential(for: service.id)?.isEmpty ?? true)
    }

    var body: some View {
        formContent
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showCredential) {
            if let definition {
                CredentialSheet(definition: definition, service: service)
            }
        }
        .confirmationDialog(
            "清除「\(service.name)」的凭据？",
            isPresented: $showClearCredentialConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                model.integrations.clearCredential(for: service.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(clearCredentialMessage)
        }
    }

    @ViewBuilder
    private var formContent: some View {
        #if os(macOS)
        macForm
        #else
        Form {
            overviewSection
            addressSection
            if let definition {
                authSection(definition)
            }
            if let definition, !definition.capabilities.isEmpty {
                capabilitySection(definition)
            }
            notificationSection
            if let definition, definition.supportsReminders {
                reminderSection
            }
            displaySection
            if definition != nil {
                openSection
            }
            maintenanceSection
        }
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    @Environment(\.interfaceScale) private var scale

    /// 与设置页同一套分组卡片。`Form` 在 macOS 上是两列布局、没有卡片背景，
    /// `NavigationLink` 还会被拆成「标签 + 值」两列，整页看起来就是裸文本。
    private var macForm: some View {
        MacSettingsPage {
            MacSettingsGroup(title: "概览", footer: overviewFooterText) {
                MacSettingsStackRow { overviewHeader }

                MacSettingsDivider()

                MacSettingsRow(title: "当前地址") {
                    Text(resolvedURL?.absoluteString ?? "未配置")
                        .zmFont(.caption, design: .monospaced)
                        .foregroundStyle(resolvedURL == nil ? Color.orange : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                MacSettingsDivider()

                MacSettingsRow(title: "可达性") {
                    HStack(spacing: 5) {
                        Image(systemName: health.symbol)
                            .zmFont(.caption2)
                            .foregroundStyle(health.isUsable ? Color.green : Color.secondary)
                        Text(health.title)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            MacSettingsGroup(title: "地址", footer: addressFooter) {
                MacSettingsRow(title: "自定义地址", fillsWidth: true) {
                    TextField("留空则用全局接入方式", text: urlOverrideBinding)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("自定义地址")
                }
            }

            if let definition {
                authGroup(definition)
            }

            if let definition, !definition.capabilities.isEmpty {
                capabilityGroup(definition)
            }

            MacSettingsGroup(title: "通知", footer: notificationFooter) {
                MacSettingsRow(title: "参与通知同步") {
                    Toggle("参与通知同步", isOn: boolBinding(\.notificationsEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("参与通知同步")
                }

                MacSettingsDivider()

                MacSettingsRow(title: "通知流路径", fillsWidth: true) {
                    TextField("例如 /api/notifications", text: stringBinding(\.feedPath))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("通知流路径")
                }

                MacSettingsDivider()

                MacSettingsRow(title: "ntfy 主题", fillsWidth: true) {
                    TextField("例如 alerts", text: stringBinding(\.ntfyTopic))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .accessibilityLabel("ntfy 主题")
                }
            }

            if let definition, definition.supportsReminders {
                reminderGroup
            }

            MacSettingsGroup(title: "首页显示", footer: displayFooterText) {
                MacSettingsRow(title: "置顶") {
                    Toggle("置顶", isOn: boolBinding(\.isPinned))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("置顶")
                }

                MacSettingsDivider()

                MacSettingsRow(title: "在首页隐藏") {
                    Toggle("在首页隐藏", isOn: boolBinding(\.isHidden))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.zmRow(scale))
                        .accessibilityLabel("在首页隐藏")
                }
            }

            if definition != nil {
                openGroup
            }

            maintenanceGroup
        }
    }

    private var overviewHeader: some View {
        HStack(spacing: 12.zmScaled(scale)) {
            ServiceGlyph(service: service, size: 40.zmScaled(scale))
            VStack(alignment: .leading, spacing: 3.zmScaled(scale)) {
                Text(service.name)
                    .zmFont(.headline)
                Text(service.summary)
                    .zmFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let definition, definition.priority != .web {
                CapsuleTag(text: definition.priority.shortTitle, tint: .accentColor)
            }
        }
    }

    private func authGroup(_ definition: IntegrationDefinition) -> some View {
        MacSettingsGroup(title: "鉴权", footer: authFooter(definition)) {
            MacSettingsRow(title: "鉴权方式") {
                Text(definition.authKind.title)
                    .foregroundStyle(.secondary)
            }

            MacSettingsDivider()

            MacSettingsRow(title: "状态") {
                HStack(spacing: 5) {
                    Circle()
                        .fill(credentialState.tint)
                        .frame(width: 7, height: 7)
                    Text(credentialState.title)
                        .foregroundStyle(.secondary)
                }
            }

            if let last = integrationPreference.lastValidatedAt {
                MacSettingsDivider()

                MacSettingsRow(title: "最近验证") {
                    Text(RelativeTime.short(last))
                        .foregroundStyle(.secondary)
                }
            }

            if let expires = integrationPreference.credentialExpiresAt {
                MacSettingsDivider()

                MacSettingsRow(title: "凭据到期") {
                    Text(expires.formatted(.dateTime.year().month().day().hour().minute()))
                        .foregroundStyle(.secondary)
                }
            }

            if let failure = model.integrations.lastErrors[service.id] {
                MacSettingsDivider()

                MacSettingsStackRow {
                    Text(failure)
                        .zmFont(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            MacSettingsDivider()

            MacSettingsButtonRow(
                title: isValidating ? "验证中…" : credentialActionTitle(definition),
                systemImage: "key"
            ) {
                if definition.authKind == .none {
                    Task { await validate(definition) }
                } else {
                    showCredential = true
                }
            }
            .disabled(definition.authKind == .none && (isValidating || resolvedURL == nil))

            if definition.authKind.needsCredential && hasStoredCredential {
                MacSettingsDivider()

                MacSettingsButtonRow(title: "重新验证", systemImage: "checkmark.shield") {
                    Task { await validate(definition) }
                }
                .disabled(isValidating || resolvedURL == nil)

                MacSettingsDivider()

                MacSettingsButtonRow(title: "清除凭据", systemImage: "trash", role: .destructive) {
                    showClearCredentialConfirm = true
                }
            }
        }
    }

    private func capabilityGroup(_ definition: IntegrationDefinition) -> some View {
        let entries: [(symbol: String, title: String)] =
            definition.reads.map { (symbol: "eye", title: $0.title) }
            + definition.writes.map { (symbol: "square.and.pencil", title: $0.title) }

        return MacSettingsGroup(title: "原生能力", footer: definition.webOnlyNote) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                MacSettingsStackRow {
                    Label(entry.title, systemImage: entry.symbol)
                        .zmFont(.subheadline)
                }
                if index < entries.count - 1 {
                    MacSettingsDivider()
                }
            }
        }
    }

    private var reminderGroup: some View {
        MacSettingsGroup(title: "提醒", footer: reminderFooterText) {
            MacSettingsRow(title: "启用本地提醒") {
                Toggle("启用本地提醒", isOn: preferenceBinding(\.remindersEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.zmRow(scale))
                    .accessibilityLabel("启用本地提醒")
            }

            if integrationPreference.remindersEnabled {
                MacSettingsDivider()

                MacSettingsRow(title: "提醒时刻") {
                    DatePicker("提醒时刻", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("提醒时刻")
                }

                if service.id == "qiansi" {
                    MacSettingsDivider()

                    MacSettingsRow(title: "约会提前") {
                        HStack(spacing: 8) {
                            Text("\(integrationPreference.eventLeadDays) 天")
                                .foregroundStyle(.secondary)
                            Stepper("约会提前", value: preferenceBinding(\.eventLeadDays), in: 0...7)
                                .labelsHidden()
                                .accessibilityLabel("约会提前")
                        }
                    }
                }

                MacSettingsDivider()

                MacSettingsRow(title: "已排程") {
                    Text("\(model.integrations.reminderCounts[service.id] ?? 0) 条")
                        .foregroundStyle(.secondary)
                }

                if model.authorization == .denied {
                    MacSettingsDivider()

                    MacSettingsStackRow {
                        warningText("系统通知权限已关闭，提醒不会送达。请到系统设置里为众妙开启通知。")
                    }
                } else if model.authorization == .notDetermined {
                    MacSettingsDivider()

                    MacSettingsButtonRow(title: "开启通知权限", systemImage: "bell.badge") {
                        Task { await model.requestNotificationPermission() }
                    }
                }
            }
        }
    }

    private var openGroup: some View {
        MacSettingsGroup(title: "打开方式", footer: openFooterText) {
            MacSettingsRow(title: "优先使用网页版") {
                Toggle("优先使用网页版", isOn: preferenceBinding(\.preferWeb))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.zmRow(scale))
                    .accessibilityLabel("优先使用网页版")
            }

            if let resolvedURL {
                MacSettingsDivider()

                MacSettingsNavigationRow(title: "打开原生页", systemImage: "rectangle.on.rectangle") {
                    NativeServiceScreen(service: service, target: nil)
                }

                MacSettingsDivider()

                MacSettingsNavigationRow(title: "打开网页版", systemImage: "safari") {
                    ServiceScreen(service: service, initialURL: resolvedURL)
                }
            } else {
                MacSettingsDivider()

                MacSettingsStackRow {
                    Text("还没有可用的服务地址，请先在上面填写自定义地址，或到「设置 → 接入方式」检查全局配置。")
                        .zmFont(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var maintenanceGroup: some View {
        MacSettingsGroup(title: "诊断与维护", footer: maintenanceFooterText) {
            MacSettingsButtonRow(title: "检测连通性", systemImage: "waveform.path.ecg") {
                model.probe(service)
                model.toast = "正在检测 \(service.name)"
            }

            if let latest = model.health[service.id] {
                MacSettingsDivider()

                MacSettingsRow(title: "检测结果") {
                    Text(latest.title)
                        .foregroundStyle(.secondary)
                }
            }

            MacSettingsDivider()

            MacSettingsButtonRow(title: "复制地址", systemImage: "doc.on.doc") {
                if let resolvedURL {
                    Pasteboard.copy(resolvedURL.absoluteString)
                    model.toast = "地址已复制"
                }
            }
            .disabled(resolvedURL == nil)

            MacSettingsDivider()

            MacSettingsButtonRow(title: "在浏览器打开", systemImage: "safari") {
                if let resolvedURL { Platform.openExternally(resolvedURL) }
            }
            .disabled(resolvedURL == nil)

            MacSettingsDivider()

            MacSettingsButtonRow(title: "恢复默认设置", systemImage: "arrow.uturn.backward", role: .destructive) {
                model.resetService(service.id)
                model.toast = "已恢复默认"
            }
        }
    }

    private var overviewFooterText: String {
        "这一页是「\(service.name)」的全部配置。地址、鉴权、通知通道、提醒与首页显示都在这里改，不再需要到别处找第二处入口。「可达性」是首页 GET 请求的结果，「鉴权」里的状态是凭据是否验证通过——两者独立，地址错会同时表现为不可达与验证失败。"
    }

    private var displayFooterText: String {
        "置顶只改变卡片在所属分类里的顺序。隐藏只是把卡片从首页撤下，通知同步与地址解析都不受影响；隐藏后仍能在「设置 → 服务」里找到并恢复。"
    }

    private var openFooterText: String {
        "开启「优先使用网页版」后首页卡片与通知都会回到网页版，关闭即恢复原生界面。"
    }

    private var reminderFooterText: String {
        "关闭提醒会立即取消已排程的条目；开启或修改时刻后，会立即按已缓存的数据重排，尚未缓存过的应用需先打开一次。"
    }

    private var maintenanceFooterText: String {
        "「恢复默认设置」只重置这个服务的地址覆盖、通知通道与首页显示，不动钥匙串里的凭据。内置默认值来自各仓库的部署配置，与实际域名/端口不一致时以这里填写的为准。全部服务的连通性可到「设置 → 诊断」一键检测。"
    }
    #endif

    // MARK: - 概览

    private var overviewSection: some View {
        Section {
            HStack(spacing: 12) {
                ServiceGlyph(service: service, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                        .zmFont(.headline)
                    Text(service.summary)
                        .zmFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if let definition, definition.priority != .web {
                    CapsuleTag(text: definition.priority.shortTitle, tint: .accentColor)
                }
            }
            .padding(.vertical, 2)

            LabeledContent("当前地址") {
                Text(resolvedURL?.absoluteString ?? "未配置")
                    .zmFont(.caption, design: .monospaced)
                    .foregroundStyle(resolvedURL == nil ? Color.orange : Color.secondary)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("可达性") {
                HStack(spacing: 5) {
                    Image(systemName: health.symbol)
                        .zmFont(.caption2)
                        .foregroundStyle(health.isUsable ? Color.green : Color.secondary)
                    Text(health.title)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("这一页是「\(service.name)」的全部配置。地址、鉴权、通知通道、提醒与首页显示都在这里改，不再需要到别处找第二处入口。「可达性」是首页 GET 请求的结果，「鉴权」里的状态是凭据是否验证通过——两者独立，地址错会同时表现为不可达与验证失败。")
        }
    }

    // MARK: - 地址

    private var addressSection: some View {
        Section {
            TextField("自定义地址（留空则用全局接入方式）", text: urlOverrideBinding)
                .zmPlainTextInput()
                #if os(iOS)
                .keyboardType(.URL)
                #endif
        } header: {
            Text("地址")
        } footer: {
            Text(addressFooter)
        }
    }

    private var addressFooter: String {
        if service.id == "ntfy" {
            return "留空即按「设置 → 接入方式」解析出 ntfy 子域。填 https://ntfy.你的域名 可单独指定；这一项同时也是 ntfy 主题浏览与通知同步用的服务器地址，原来「ntfy 主题」页里的那一处在 0.9 之后并入这里。"
        }
        return "Nginx + HTTPS 子域名场景下留空即可。只有局域网排障、或该服务被单独映射到别的域名/端口时才需要填，例如 http://192.168.1.10:8787（宿主机映射端口，不是容器内部端口）。"
    }

    // MARK: - 鉴权

    private func authSection(_ definition: IntegrationDefinition) -> some View {
        Section {
            LabeledContent("鉴权方式", value: definition.authKind.title)

            LabeledContent("状态") {
                HStack(spacing: 5) {
                    Circle()
                        .fill(credentialState.tint)
                        .frame(width: 7, height: 7)
                    Text(credentialState.title)
                        .foregroundStyle(.secondary)
                }
            }

            if let last = integrationPreference.lastValidatedAt {
                LabeledContent("最近验证", value: RelativeTime.short(last))
            }

            if let expires = integrationPreference.credentialExpiresAt {
                LabeledContent("凭据到期", value: expires.formatted(.dateTime.year().month().day().hour().minute()))
            }

            if let failure = model.integrations.lastErrors[service.id] {
                Text(failure)
                    .zmFont(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                if definition.authKind == .none {
                    Task { await validate(definition) }
                } else {
                    showCredential = true
                }
            } label: {
                HStack {
                    if definition.authKind == .none && isValidating {
                        ProgressView().controlSize(.small)
                    }
                    Label(credentialActionTitle(definition), systemImage: "key")
                }
            }
            .disabled(definition.authKind == .none && (isValidating || resolvedURL == nil))

            if definition.authKind.needsCredential && hasStoredCredential {
                Button {
                    Task { await validate(definition) }
                } label: {
                    HStack {
                        if isValidating { ProgressView().controlSize(.small) }
                        Label("重新验证", systemImage: "checkmark.shield")
                    }
                }
                .disabled(isValidating || resolvedURL == nil)

                Button(role: .destructive) {
                    showClearCredentialConfirm = true
                } label: {
                    Label("清除凭据", systemImage: "trash")
                }
            }
        } header: {
            Text("鉴权")
        } footer: {
            Text(authFooter(definition))
        }
    }

    private func credentialActionTitle(_ definition: IntegrationDefinition) -> String {
        switch definition.authKind {
        case .none:
            return "测试连接"
        default:
            if credentialState.isUsable { return "修改凭据" }
            return hasStoredCredential ? "重新填写凭据" : "配置凭据"
        }
    }

    private func authFooter(_ definition: IntegrationDefinition) -> String {
        var parts: [String] = []
        if definition.authKind == .none {
            parts.append("该应用没有鉴权，直接测连通性即可。")
        } else {
            parts.append("凭据保存在系统钥匙串（仅本机、不参与 iCloud 同步），先验证后保存，验证失败不会覆盖当前可用的凭据。")
        }
        switch service.id {
        case "mujian":
            parts.append("这里的访问令牌同时是「演出提醒」拉取幕间数据用的那一份，输入一次即可，不必再单独填写。")
        case "ntfy":
            parts.append("服务端启用 auth-file 时必须带令牌；「标记已读」要求令牌对该主题有写权限，否则已读状态只留在本机。")
        default:
            break
        }
        if definition.priority == .web {
            parts.append("该应用保留网页版，凭据只服务于连通性检测与通知。")
        }
        return parts.joined(separator: "\n")
    }

    private var clearCredentialMessage: String {
        service.id == "mujian"
            ? "网页版的登录状态不受影响；演出提醒会同时失去令牌。原生提醒会一并撤销。"
            : "网页版的登录状态不受影响；原生提醒会一并撤销。"
    }

    // MARK: - 原生能力

    private func capabilitySection(_ definition: IntegrationDefinition) -> some View {
        Section {
            ForEach(definition.reads, id: \.self) { capability in
                Label(capability.title, systemImage: "eye")
                    .zmFont(.subheadline)
            }
            ForEach(definition.writes, id: \.self) { capability in
                Label(capability.title, systemImage: "square.and.pencil")
                    .zmFont(.subheadline)
            }
        } header: {
            Text("原生能力")
        } footer: {
            Text(definition.webOnlyNote)
        }
    }

    // MARK: - 通知

    private var notificationSection: some View {
        Section {
            Toggle("参与通知同步", isOn: boolBinding(\.notificationsEnabled))

            TextField("通知流路径", text: stringBinding(\.feedPath))
                .zmPlainTextInput()

            TextField("ntfy 主题", text: stringBinding(\.ntfyTopic))
                .zmPlainTextInput()
        } header: {
            Text("通知")
        } footer: {
            Text(notificationFooter)
        }
    }

    private var notificationFooter: String {
        var text = "通知流路径指向实现 GET <路径>?since=ISO8601&limit=50 的接口。ntfy 主题则直接从自托管 ntfy 拉取，无需改应用代码。两者可只配一个。"
        if service.id == "ntfy" {
            text += "\nntfy 自身的主题订阅在「设置 → ntfy 主题」里管理；这里填的是把 ntfy 当作通知来源时的主题名。"
        }
        return text
    }

    // MARK: - 提醒

    private var reminderSection: some View {
        Section {
            Toggle("启用本地提醒", isOn: preferenceBinding(\.remindersEnabled))

            #if os(iOS)
            Toggle("同时写入系统日历与提醒事项", isOn: systemRemindersBinding)
                .accessibilityHint("会在系统日历与提醒事项里创建名为众妙的条目，关闭后自动清理")
            #endif

            if integrationPreference.remindersEnabled {
                DatePicker(
                    "提醒时刻",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )

                if service.id == "qiansi" {
                    Stepper(value: preferenceBinding(\.eventLeadDays), in: 0...7) {
                        LabeledContent("约会提前", value: "\(integrationPreference.eventLeadDays) 天")
                    }
                }

                LabeledContent("已排程", value: "\(model.integrations.reminderCounts[service.id] ?? 0) 条")

                #if os(iOS)
                if integrationPreference.systemRemindersEnabled {
                    LabeledContent(
                        "系统内",
                        value: "\(model.integrations.systemReminderCounts[service.id] ?? 0) 条"
                    )
                    if let note = model.integrations.systemReminderNotes[service.id] {
                        warningText(note)
                    }
                }
                #endif

                if model.authorization == .denied {
                    warningText("系统通知权限已关闭，提醒不会送达。请到系统设置里为众妙开启通知。")
                } else if model.authorization == .notDetermined {
                    Button {
                        Task { await model.requestNotificationPermission() }
                    } label: {
                        Label("开启通知权限", systemImage: "bell.badge")
                    }
                }
            }
        } header: {
            Text("提醒")
        } footer: {
            Text("关闭提醒会立即取消已排程的条目；开启或修改时刻后，会立即按已缓存的数据重排，尚未缓存过的应用需先打开一次。\(systemReminderFooter)")
        }
    }

    /// 橙色小字在浅色背景下对比度不足；用图标承担颜色，正文保持主文字色。
    private func warningText(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .zmFont(.caption)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
                .zmFont(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 系统写入的说明。免费账号没有推送，这是唯一能长期可靠到点的通道。
    private var systemReminderFooter: String {
        #if os(iOS)
        if integrationPreference.systemRemindersEnabled {
            return "\n写入系统时会在「日历」与「提醒事项」里建立名为「众妙」的列表，"
                + "只增删它自己写进去的条目。到点由系统触发，不占上面的 48 条预算。"
        }
        return "\n也可写入系统日历与提醒事项：由系统持有，App 不运行也到点，适合远期与每年重复的提醒。"
        #else
        return ""
        #endif
    }

    // MARK: - 首页显示

    private var displaySection: some View {
        Section {
            Toggle("置顶", isOn: boolBinding(\.isPinned))
            Toggle("在首页隐藏", isOn: boolBinding(\.isHidden))
        } header: {
            Text("首页显示")
        } footer: {
            Text("置顶只改变卡片在所属分类里的顺序。隐藏只是把卡片从首页撤下，通知同步与地址解析都不受影响；隐藏后仍能在「设置 → 服务」里找到并恢复。")
        }
    }

    // MARK: - 打开方式

    private var openSection: some View {
        Section {
            Toggle("优先使用网页版", isOn: preferenceBinding(\.preferWeb))

            if let resolvedURL {
                NavigationLink {
                    NativeServiceScreen(service: service, target: nil)
                } label: {
                    Label("打开原生页", systemImage: "rectangle.on.rectangle")
                }

                NavigationLink {
                    ServiceScreen(service: service, initialURL: resolvedURL)
                } label: {
                    Label("打开网页版", systemImage: "safari")
                }
            } else {
                Text("还没有可用的服务地址，请先在上面填写自定义地址，或到「设置 → 接入方式」检查全局配置。")
                    .zmFont(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("打开方式")
        } footer: {
            Text("开启「优先使用网页版」后首页卡片与通知都会回到网页版，关闭即恢复原生界面。")
        }
    }

    // MARK: - 诊断与维护

    private var maintenanceSection: some View {
        Section {
            Button {
                model.probe(service)
                model.toast = "正在检测 \(service.name)"
            } label: {
                Label("检测连通性", systemImage: "waveform.path.ecg")
            }

            if let latest = model.health[service.id] {
                LabeledContent("检测结果", value: latest.title)
            }

            Button {
                if let resolvedURL {
                    Pasteboard.copy(resolvedURL.absoluteString)
                    model.toast = "地址已复制"
                }
            } label: {
                Label("复制地址", systemImage: "doc.on.doc")
            }
            .disabled(resolvedURL == nil)

            Button {
                if let resolvedURL { Platform.openExternally(resolvedURL) }
            } label: {
                Label("在浏览器打开", systemImage: "safari")
            }
            .disabled(resolvedURL == nil)

            Button(role: .destructive) {
                model.resetService(service.id)
                model.toast = "已恢复默认"
            } label: {
                Label("恢复默认设置", systemImage: "arrow.uturn.backward")
            }
        } header: {
            Text("诊断与维护")
        } footer: {
            Text("「恢复默认设置」只重置这个服务的地址覆盖、通知通道与首页显示，不动钥匙串里的凭据。内置默认值来自各仓库的部署配置，与实际域名/端口不一致时以这里填写的为准。全部服务的连通性可到「设置 → 诊断」一键检测。")
        }
    }

    // MARK: - 绑定与动作

    private func validate(_ definition: IntegrationDefinition) async {
        guard let baseURL = resolvedURL else { return }
        isValidating = true
        await model.integrations.validateIfConfigured(serviceID: service.id, baseURL: baseURL)
        isValidating = false
    }

    private var urlOverrideBinding: Binding<String> {
        Binding(
            get: { model.settings.preference(for: service).urlOverride ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                model.updateSettings { settings in
                    settings.update(service.id) { preference in
                        preference.urlOverride = trimmed.isEmpty ? nil : newValue
                    }
                }
                // ntfy 的地址同时决定主题浏览与通知同步，改完立刻重算。
                if service.id == "ntfy" {
                    Task { _ = await model.loadServerNtfyTopics() }
                }
            }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<ServicePreference, String?>) -> Binding<String> {
        Binding(
            get: { model.settings.preference(for: service)[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                model.updateSettings { settings in
                    settings.update(service.id) { preference in
                        preference[keyPath: keyPath] = trimmed.isEmpty ? nil : newValue
                    }
                }
            }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ServicePreference, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings.preference(for: service)[keyPath: keyPath] },
            set: { newValue in
                model.updateSettings { settings in
                    settings.update(service.id) { preference in
                        preference[keyPath: keyPath] = newValue
                    }
                }
            }
        )
    }

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<IntegrationPreference, Value>) -> Binding<Value> {
        Binding(
            get: { integrationPreference[keyPath: keyPath] },
            set: { value in
                model.integrations.updatePreference(service.id) { $0[keyPath: keyPath] = value }
            }
        )
    }

    #if os(iOS)
    /// 关闭系统写入时的清理由 `IntegrationCenter.updatePreference` 统一处理，
    /// 保证从设置页和原生页改开关都走同一条路径。
    private var systemRemindersBinding: Binding<Bool> {
        Binding(
            get: { integrationPreference.systemRemindersEnabled },
            set: { newValue in
                model.integrations.updatePreference(service.id) {
                    $0.systemRemindersEnabled = newValue
                }
            }
        )
    }
    #endif

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: integrationPreference.reminderHour,
                    minute: integrationPreference.reminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.integrations.updatePreference(service.id) {
                    $0.reminderHour = components.hour ?? 9
                    $0.reminderMinute = components.minute ?? 0
                }
            }
        )
    }
}
