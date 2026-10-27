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

    // MARK: - 概览

    private var overviewSection: some View {
        Section {
            HStack(spacing: 12) {
                ServiceGlyph(service: service, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.name)
                        .font(.headline)
                    Text(service.summary)
                        .font(.caption)
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
                    .font(.caption.monospaced())
                    .foregroundStyle(resolvedURL == nil ? Color.orange : Color.secondary)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("可达性") {
                HStack(spacing: 5) {
                    Image(systemName: health.symbol)
                        .font(.caption2)
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
                    .font(.caption)
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
                    .font(.subheadline)
            }
            ForEach(definition.writes, id: \.self) { capability in
                Label(capability.title, systemImage: "square.and.pencil")
                    .font(.subheadline)
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

                if model.authorization == .denied {
                    Text("系统通知权限已关闭，提醒不会送达。请到系统设置里为众妙开启通知。")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
            Text("提醒按最近一次刷新的数据排程；修改时刻后回到原生页刷新即可重排。")
        }
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
                    .font(.caption)
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
