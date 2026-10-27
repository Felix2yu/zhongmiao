import SwiftUI
import ZhongmiaoCore

/// 账号/令牌录入与验证。原生页横幅与设置详情共用。
struct CredentialSheet: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let definition: IntegrationDefinition
    let service: ServiceDefinition

    @State private var token = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var didPrefill = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("应用", value: service.name)
                    LabeledContent("鉴权", value: definition.authKind.title)
                    LabeledContent("当前状态", value: model.integrations.state(for: definition.serviceID).title)
                } header: {
                    Text("接入")
                } footer: {
                    Text("凭据保存在系统钥匙串（仅本机、不随 iCloud 同步），不会写入日志。")
                }

                Section {
                    switch definition.authKind {
                    case .none:
                        Text("该应用没有鉴权，直接测试连接即可。")
                            .foregroundStyle(.secondary)
                    case .bearerToken:
                        SecureField("访问令牌 / API Key", text: $token)
                            .zmPlainTextInput()
                        if !existingToken.isEmpty {
                            Text("已保存令牌；留空表示不修改。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .login, .sessionCookie:
                        TextField("账号", text: $username)
                            .zmPlainTextInput()
                        SecureField(hasStoredPassword ? "密码（留空则不修改）" : "密码", text: $password)
                            .zmPlainTextInput()
                    }
                } header: {
                    Text("凭据")
                } footer: {
                    Text(authFooter)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text(isSaving ? "正在验证…" : "保存并验证")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("\(service.name) · 接入")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task {
                guard !didPrefill else { return }
                didPrefill = true
                if let credential = model.integrations.credential(for: definition.serviceID) {
                    username = credential.username ?? ""
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var existingToken: String {
        model.integrations.credential(for: definition.serviceID)?.token ?? ""
    }

    private var hasStoredPassword: Bool {
        !(model.integrations.credential(for: definition.serviceID)?.password ?? "").isEmpty
    }

    private var authFooter: String {
        switch definition.authKind {
        case .none:
            "无鉴权应用不需要凭据。"
        case .bearerToken:
            definition.credentialOptional
                ? "服务端没有开启访问控制时可以留空，直接保存并验证。"
                : "填写服务端配置的访问令牌。"
        case .login:
            "账号密码只用于换取登录令牌；验证成功后保存。"
        case .sessionCookie:
            "账号密码只用于换取 30 天会话；验证成功后保存。"
        }
    }

    private func save() async {
        guard let baseURL = model.url(for: service) else {
            message = "还没有可用的服务地址，请先到「设置 → 接入方式」配置。"
            return
        }
        isSaving = true
        message = nil

        var input = IntegrationCredentialInput()
        if definition.authKind == .bearerToken {
            input.token = token.isEmpty ? nil : token
        }
        if definition.authKind == .login || definition.authKind == .sessionCookie {
            input.username = username.isEmpty ? nil : username
            input.password = password.isEmpty ? nil : password
        }

        let ok = await model.integrations.saveAndValidate(
            serviceID: definition.serviceID,
            baseURL: baseURL,
            input: input
        )
        isSaving = false
        if ok {
            model.toast = "\(service.name) 已连接"
            dismiss()
        } else {
            message = model.integrations.lastErrors[definition.serviceID] ?? "验证失败"
        }
    }
}
