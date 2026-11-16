import SwiftUI

/// 旧版设置里的密钥输入。值在 Keychain，界面上只显示“已保存/未设置”。
struct SecretField: View {

    @Environment(AppModel.self) private var model
    let title: String
    let key: SecretStore.LegacyKey
    var footer: String?
    var onSave: (() -> Void)?

    @State private var editing = false
    @State private var draft = ""
    @State private var error: String?

    private var stored: String { model.integrations.secrets.value(for: key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if editing {
                SecureField(title, text: $draft)
                    .zmPlainTextInput()

                HStack(spacing: 14) {
                    Button("保存") { save() }
                        .secretActionStyle()
                        .zmFont(.subheadline, weight: .semibold)
                    Button("取消") {
                        editing = false
                        draft = ""
                        error = nil
                    }
                    .secretActionStyle()
                    .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent(title) {
                    Text(stored.isEmpty ? "未设置" : "已保存")
                        .foregroundStyle(stored.isEmpty ? .secondary : .primary)
                }
                // 在自绘卡片里 VStack 只给内容理想宽度，不加这句「未设置」会紧贴标题，
                // 与其他行的「标签靠左、值靠右」对不齐。
                .frame(maxWidth: .infinity)

                HStack(spacing: 14) {
                    Button(stored.isEmpty ? "填写" : "修改") {
                        draft = ""
                        editing = true
                    }
                    .secretActionStyle()
                    .zmFont(.subheadline, weight: .semibold)

                    if !stored.isEmpty {
                        Button("清除", role: .destructive) {
                            do {
                                try model.integrations.secrets.setValue("", for: key)
                                onSave?()
                            } catch {
                                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                        .secretActionStyle(role: .destructive)
                        .zmFont(.subheadline)
                    }
                }
            }

            if let error {
                Text(error)
                    .zmFont(.caption)
                    .foregroundStyle(.orange)
            }
            if let footer {
                Text(footer)
                    .zmFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        do {
            try model.integrations.secrets.setValue(draft, for: key)
            editing = false
            draft = ""
            error = nil
            onSave?()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private extension View {
    /// 密钥行里的动作按钮。macOS 上系统的 `.borderless`/`.bordered` 叠在卡片上只有一层
    /// 几乎透明的底，看着就是纯文字，所以换成自绘的 push 样式；iOS 保持原来的无边框文字按钮。
    func secretActionStyle(role: ButtonRole? = nil) -> some View {
        #if os(macOS)
        zmPushButton(role: role)
        #else
        buttonStyle(.borderless)
        #endif
    }
}
