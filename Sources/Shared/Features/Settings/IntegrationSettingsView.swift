import SwiftUI
import ZhongmiaoCore

struct IntegrationSettingsView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Text("有 API 的应用优先走原生界面；高级、低频操作仍可跳网页版。凭据保存在系统钥匙串。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(IntegrationCatalog.grouped, id: \.priority) { group in
                Section {
                    ForEach(group.definitions) { definition in
                        if let service = ServiceCatalog.service(id: definition.serviceID) {
                            NavigationLink {
                                IntegrationDetailView(definition: definition, service: service)
                            } label: {
                                row(definition: definition, service: service)
                            }
                        }
                    }
                } header: {
                    Text(group.priority.title)
                }
            }
        }
        .navigationTitle("应用接入")
        .task { await model.integrations.refreshReminderCounts() }
    }

    private func row(definition: IntegrationDefinition, service: ServiceDefinition) -> some View {
        let state = model.integrations.state(for: definition.serviceID)
        return HStack(spacing: 10) {
            ServiceGlyph(service: service, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.subheadline.weight(.medium))
                Text(definition.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    CapsuleTag(text: definition.authKind == .none ? "无需鉴权" : definition.authKind.title)
                    if definition.supportsReminders {
                        CapsuleTag(text: "提醒", systemImage: "bell")
                    }
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Circle()
                    .fill(state.tint)
                    .frame(width: 7, height: 7)
                Text(state.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }
}

struct IntegrationDetailView: View {

    @Environment(AppModel.self) private var model

    let definition: IntegrationDefinition
    let service: ServiceDefinition

    @State private var showCredential = false
    @State private var showClearConfirm = false
    @State private var isValidating = false

    private var state: IntegrationCenter.CredentialState {
        model.integrations.state(for: definition.serviceID)
    }

    private var preference: IntegrationPreference {
        model.integrations.preference(for: definition.serviceID)
    }

    private var baseURL: URL? {
        model.url(for: service)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ServiceGlyph(service: service, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.name)
                            .font(.headline)
                        Text(definition.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    CapsuleTag(text: definition.priority.shortTitle, tint: .accentColor)
                }

                LabeledContent("鉴权", value: definition.authKind.title)
                LabeledContent("状态") {
                    HStack(spacing: 5) {
                        Circle().fill(state.tint).frame(width: 7, height: 7)
                        Text(state.title)
                            .foregroundStyle(.secondary)
                    }
                }
                if let last = preference.lastValidatedAt {
                    LabeledContent("最近验证", value: RelativeTime.short(last))
                }
                if let expires = preference.credentialExpiresAt {
                    LabeledContent("凭据到期", value: expires.formatted(.dateTime.year().month().day().hour().minute()))
                }
                if let failure = model.integrations.lastErrors[definition.serviceID] {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("接入状态")
            } footer: {
                Text("原生请求直接访问该应用自己的 API；网页版登录态与原生凭据互不影响。")
            }

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

            Section {
                Button {
                    showCredential = true
                } label: {
                    Label(
                        definition.authKind == .none ? "测试连接" : (state.isUsable ? "修改凭据" : "配置凭据"),
                        systemImage: "key"
                    )
                }

                if definition.authKind != .none && !isEmptyCredential {
                    Button {
                        Task {
                            isValidating = true
                            if let baseURL {
                                await model.integrations.validateIfConfigured(
                                    serviceID: definition.serviceID,
                                    baseURL: baseURL
                                )
                            }
                            isValidating = false
                        }
                    } label: {
                        HStack {
                            if isValidating { ProgressView().controlSize(.small) }
                            Label("重新验证", systemImage: "checkmark.shield")
                        }
                    }
                    .disabled(isValidating || baseURL == nil)

                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清除凭据", systemImage: "trash")
                    }
                }
            } header: {
                Text("凭据")
            } footer: {
                Text("先验证后保存；验证失败不会覆盖当前可用凭据。")
            }

            if definition.supportsReminders {
                reminderSection
            }

            Section {
                Toggle("优先使用网页版", isOn: preferenceBinding(\.preferWeb))
            } header: {
                Text("打开方式")
            } footer: {
                Text("开启后首页卡片与通知都会回到网页版；关闭即恢复原生界面。")
            }

            Section {
                if let baseURL {
                    NavigationLink {
                        NativeServiceScreen(service: service)
                    } label: {
                        Label("打开原生页", systemImage: "rectangle.on.rectangle")
                    }

                    NavigationLink {
                        ServiceScreen(service: service, initialURL: baseURL)
                    } label: {
                        Label("打开网页版", systemImage: "safari")
                    }
                } else {
                    Text("还没有可用的服务地址，请先到「设置 → 接入方式」配置。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("打开")
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
        .confirmationDialog(
            "清除「\(service.name)」的原生凭据？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                model.integrations.clearCredential(for: definition.serviceID)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("网页版的登录状态不受影响；原生提醒会一并撤销。")
        }
    }

    private var isEmptyCredential: Bool {
        model.integrations.credential(for: definition.serviceID)?.isEmpty ?? true
    }


    @ViewBuilder
    private var reminderSection: some View {
        Section {
            Toggle("启用本地提醒", isOn: preferenceBinding(\.remindersEnabled))

            if preference.remindersEnabled {
                DatePicker(
                    "提醒时刻",
                    selection: reminderTimeBinding,
                    displayedComponents: .hourAndMinute
                )

                if definition.serviceID == "qiansi" {
                    Stepper(value: preferenceBinding(\.eventLeadDays), in: 0...7) {
                        LabeledContent("约会提前", value: "\(preference.eventLeadDays) 天")
                    }
                }

                LabeledContent("已排程", value: "\(model.integrations.reminderCounts[definition.serviceID] ?? 0) 条")

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

    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<IntegrationPreference, Value>) -> Binding<Value> {
        Binding(
            get: { preference[keyPath: keyPath] },
            set: { value in
                model.integrations.updatePreference(definition.serviceID) { $0[keyPath: keyPath] = value }
            }
        )
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: preference.reminderHour,
                    minute: preference.reminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.integrations.updatePreference(definition.serviceID) {
                    $0.reminderHour = components.hour ?? 9
                    $0.reminderMinute = components.minute ?? 0
                }
            }
        )
    }
}
