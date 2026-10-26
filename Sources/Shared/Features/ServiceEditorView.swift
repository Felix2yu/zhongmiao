import SwiftUI
import ZhongmiaoCore

struct ServiceEditorView: View {

    let service: ServiceDefinition

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ServiceGlyph(service: service, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.name)
                            .font(.headline)
                        Text(service.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                LabeledContent("当前地址") {
                    Text(model.url(for: service)?.absoluteString ?? "无法解析")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                TextField("自定义地址（留空则用全局设置）", text: stringBinding(\.urlOverride))
                    .zmPlainTextInput()
                    #if os(iOS)
                    .keyboardType(.URL)
                    #endif
            } header: {
                Text("地址")
            } footer: {
                Text("Nginx + HTTPS 子域名场景下留空即可，走全局子域名解析。只有在局域网排障、或某个服务被单独映射到别的端口/域名时才需要填，例如 http://192.168.1.10:8787（这里是宿主机映射端口，不是容器内部端口）。")
            }

            Section {
                Toggle("参与后台同步", isOn: boolBinding(\.notificationsEnabled))

                TextField("通知流路径", text: stringBinding(\.feedPath))
                    .zmPlainTextInput()

                TextField("ntfy 主题", text: stringBinding(\.ntfyTopic))
                    .zmPlainTextInput()
            } header: {
                Text("通知")
            } footer: {
                Text("通知流路径指向实现 GET <路径>?since=ISO8601&limit=50 的接口。ntfy 主题则直接从自托管 ntfy 拉取，无需改应用代码。两者可只配一个。")
            }

            Section {
                Button {
                    model.probe(service)
                    model.toast = "正在检测 \(service.name)"
                } label: {
                    Label("检测连通性", systemImage: "waveform.path.ecg")
                }

                if let health = model.health[service.id] {
                    LabeledContent("检测结果", value: health.title)
                }

                Button(role: .destructive) {
                    model.resetService(service.id)
                    model.toast = "已恢复默认"
                } label: {
                    Label("恢复默认设置", systemImage: "arrow.uturn.backward")
                }
            } footer: {
                Text("内置默认值来自各仓库的部署配置；若与你的实际域名/端口不一致，以这里填写的为准。")
            }
        }
        .navigationTitle("服务设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("完成") { dismiss() }
            }
        }
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
}
