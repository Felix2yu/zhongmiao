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
                        .font(.subheadline)
                    if preference.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("已置顶")
                    }
                    if preference.isHidden {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("首页已隐藏")
                    }
                    if preference.notificationsEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("参与通知同步")
                    }
                }
                Text(resolved?.absoluteString ?? "未配置地址")
                    .font(.caption2.monospaced())
                    .foregroundStyle(resolved == nil ? Color.orange : Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(definition?.priority.shortTitle ?? "—")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.tint)
                        .frame(width: 6, height: 6)
                    Text(state.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 1)
    }
}
