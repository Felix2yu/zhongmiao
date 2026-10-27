import SwiftUI
import ZhongmiaoCore

struct ChaxinScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<ChaxinSnapshot>
    @State private var browserTarget: BrowserTarget?

    init(
        service: ServiceDefinition,
        baseURL: URL,
        definition: IntegrationDefinition,
        center: IntegrationCenter
    ) {
        self.service = service
        self.baseURL = baseURL
        self.definition = definition
        _store = State(initialValue: IntegrationSnapshotModel(
            serviceID: "chaxin",
            baseURL: baseURL,
            center: center,
            loader: {
                let client = ChaxinClient(baseURL: baseURL)
                async let repos = client.repos()
                async let notifications = client.notifications()
                return ChaxinSnapshot(
                    repos: try await repos,
                    notifications: try await notifications
                )
            }
        ))
    }

    var body: some View {
        List {
            Section {
                metrics
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }

            if let error = store.error {
                Section {
                    IntegrationStatusBanner(
                        state: store.center.state(for: "chaxin"),
                        error: error,
                        onConfigure: {},
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            if let notifications = store.snapshot?.notifications, !notifications.isEmpty {
                Section {
                    ForEach(notifications) { notification in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(notification.fullName ?? "仓库")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if notification.status == "failed" {
                                    CapsuleTag(text: "发送失败", tint: .red)
                                }
                            }
                            HStack(alignment: .firstTextBaseline) {
                                Text(notification.tag ?? "新版本")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                if let released = ChaxinDate.display(notification.releasedAt) {
                                    Text(released)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            if let urlString = notification.releaseUrl, let url = URL(string: urlString) {
                                Button {
                                    browserTarget = BrowserTarget(url: url)
                                } label: {
                                    Label("查看 Release", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    Text("版本动态")
                }
            } else {
                Section {
                    EmptyStateView(
                        symbol: "shippingbox",
                        title: "还没有发布动态",
                        message: "察新监控到新的 GitHub Release 后会显示在这里。"
                    )
                    .listRowBackground(Color.clear)
                }
            }

            if let repos = store.snapshot?.repos, !repos.isEmpty {
                Section {
                    ForEach(repos.prefix(30)) { repo in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.fullName)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(repoSubtitle(repo))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if repo.monitored == true {
                                CapsuleTag(text: "监控中", tint: .green)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    Text("仓库")
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("仓库管理与监控设置", systemImage: "safari")
                }
            } footer: {
                Text("原生不读取 /api/settings，避免把 GitHub Token 带到界面上。")
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IntegrationScreenMenu(service: service, definition: definition) {
                    Task { await store.refresh() }
                }
            }
        }
        .refreshable {
            await store.refresh()
        }
        .task {
            await store.loadCache()
            await store.refreshIfNeeded()
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .inAppBrowser($browserTarget)
    }

    private var metrics: some View {
        let repos = store.snapshot?.repos ?? []
        let monitored = repos.filter { $0.monitored == true }.count
        let notifications = store.snapshot?.notifications ?? []
        return HStack(spacing: 10) {
            metric("仓库", value: "\(repos.count)", tint: .accentColor)
            metric("监控中", value: "\(monitored)", tint: .green)
            metric("动态", value: "\(notifications.count)", tint: .orange)
        }
    }

    private func metric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func repoSubtitle(_ repo: ChaxinRepo) -> String {
        var parts: [String] = []
        if let language = repo.language, !language.isEmpty { parts.append(language) }
        if let stars = repo.stargazersCount { parts.append("★ \(stars)") }
        if let tag = repo.latestTag, !tag.isEmpty { parts.append(tag) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}
