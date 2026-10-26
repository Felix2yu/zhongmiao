import SwiftUI
import ZhongmiaoCore

struct DiagnosticsView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(ServiceCatalog.all) { service in
                    row(for: service)
                }
            } header: {
                Text("服务连通性")
            } footer: {
                Text("体检会向每个服务的首页发一次 GET 请求。返回 401/403 视为「可达但需要登录」，这对自建应用是正常状态。")
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
                if model.log.isEmpty {
                    Text("暂无日志").foregroundStyle(.secondary)
                } else {
                    ForEach(model.log, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if !model.log.isEmpty {
                    Button("清空日志", role: .destructive) {
                        model.clearLog()
                    }
                }
            } header: {
                Text("运行日志")
            } footer: {
                Text("日志只保存在本机内存中，重启后清空。")
            }
        }
        .navigationTitle("体检")
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
    private func row(for service: ServiceDefinition) -> some View {
        let health = model.health(for: service)
        let url = model.url(for: service)

        HStack(alignment: .top, spacing: 10) {
            ServiceGlyph(service: service, size: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.subheadline.weight(.medium))
                Text(url?.absoluteString ?? "未配置地址")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: health.symbol)
                        .font(.caption2)
                        .foregroundStyle(health.isUsable ? .green : .secondary)
                    Text(health.title)
                        .font(.caption2)
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
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(service.name) 的操作")
        }
        .padding(.vertical, 2)
    }

    private func bullet(_ text: String, symbol: String) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
