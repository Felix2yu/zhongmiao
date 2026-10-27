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
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                    Button("取消") {
                        editing = false
                        draft = ""
                        error = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent(title) {
                    Text(stored.isEmpty ? "未设置" : "已保存")
                        .foregroundStyle(stored.isEmpty ? .secondary : .primary)
                }

                HStack(spacing: 14) {
                    Button(stored.isEmpty ? "填写" : "修改") {
                        draft = ""
                        editing = true
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))

                    if !stored.isEmpty {
                        Button("清除", role: .destructive) {
                            do {
                                try model.integrations.secrets.setValue("", for: key)
                                onSave?()
                            } catch {
                                self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let footer {
                Text(footer)
                    .font(.caption)
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
