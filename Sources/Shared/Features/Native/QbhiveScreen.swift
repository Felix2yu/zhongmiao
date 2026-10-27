import SwiftUI
import ZhongmiaoCore

struct QbhiveScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: QbhiveModel
    @State private var showCredential = false

    init(
        service: ServiceDefinition,
        baseURL: URL,
        definition: IntegrationDefinition,
        center: IntegrationCenter
    ) {
        self.service = service
        self.baseURL = baseURL
        self.definition = definition
        _store = State(initialValue: QbhiveModel(service: service, baseURL: baseURL, center: center))
    }

    var body: some View {
        List {
            Section {
                speedCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }

            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["qbhive"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                counts
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))
            }

            Section {
                chips
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            if store.torrents.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "arrow.down.circle",
                        title: "没有符合条件的种子",
                        message: "换个筛选条件，或到网页版添加下载。"
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(store.torrents) { torrent in
                        torrentRow(torrent)
                    }
                } header: {
                    Text("种子")
                }
            }

            if let feeds = store.snapshot?.feeds, !feeds.isEmpty {
                Section {
                    ForEach(feeds) { feed in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feed.feedName ?? feed.feedId ?? "RSS")
                                    .font(.subheadline)
                                if let error = feed.lastError, !error.isEmpty {
                                    Text(error).font(.caption2).foregroundStyle(.red)
                                } else {
                                    Text("匹配 \(feed.matched ?? 0) · 下载 \(feed.downloaded ?? 0) · 失败 \(feed.failed ?? 0)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if feed.enabled == true {
                                CapsuleTag(text: "启用", tint: .green)
                            }
                        }
                    }
                } header: {
                    Text("RSS")
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("删除种子与高级设置", systemImage: "safari")
                }
            } footer: {
                Text("原生只做可逆的暂停、继续与校验；删除文件、RSS 编辑、文件管理仍在网页版。")
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
        .refreshWhenIntegrationReady(center: store.center, serviceID: "qbhive") {
            Task { await store.refresh() }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
    }

    private var bannerState: IntegrationCenter.CredentialState? {
        let state = store.center.state(for: "qbhive")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var speedCard: some View {
        let stats = store.snapshot?.stats
        return HStack(spacing: 10) {
            speedMetric("下载", value: stats?.dlSpeed ?? 0, symbol: "arrow.down", tint: .blue)
            speedMetric("上传", value: stats?.upSpeed ?? 0, symbol: "arrow.up", tint: .green)
        }
    }

    private func speedMetric(_ title: String, value: Double, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(bytesPerSecond(value))
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var counts: some View {
        let stats = store.snapshot?.stats
        return HStack(spacing: 14) {
            countItem("下载中", stats?.downloadingCount ?? 0, .blue)
            countItem("做种", stats?.seedingCount ?? 0, .green)
            countItem("错误", stats?.erroredCount ?? 0, .red)
            countItem("活动", stats?.activeCount ?? 0, .accentColor)
        }
    }

    private func countItem(_ title: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QbhiveModel.Filter.allCases) { filter in
                    Button {
                        store.filter = filter
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(store.filter == filter ? Color.white : Color.secondary)
                            .background(
                                store.filter == filter ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func torrentRow(_ torrent: QbhiveTorrent) -> some View {
        let expanded = store.expandedHash == torrent.hash
        return VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.expandedHash = expanded ? nil : torrent.hash
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(torrent.name)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        Text("\(Int((torrent.progress ?? 0) * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: min(max(torrent.progress ?? 0, 0), 1))
                        .tint(torrent.isErrored ? .red : (torrent.isSeeding ? .green : .accentColor))

                    HStack(spacing: 8) {
                        Text(torrent.state ?? "未知")
                            .font(.caption2)
                            .foregroundStyle(torrent.isErrored ? .red : .secondary)
                        if let size = torrent.size {
                            Text(formatBytes(size))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let down = torrent.dlspeed, down > 0 {
                            Text("↓" + bytesPerSecond(down))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                        if let up = torrent.upspeed, up > 0 {
                            Text("↑" + bytesPerSecond(up))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.green)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 8) {
                    if store.busyHashes.contains(torrent.hash) {
                        ProgressView().controlSize(.small)
                    }
                    if torrent.isStopped || torrent.isErrored {
                        actionButton("继续", action: "resume", torrent: torrent)
                    } else {
                        actionButton("暂停", action: "pause", torrent: torrent)
                    }
                    actionButton("校验", action: "recheck", torrent: torrent)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func actionButton(_ title: String, action: String, torrent: QbhiveTorrent) -> some View {
        Button(title) {
            Task { await store.perform(action, on: torrent) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private func bytesPerSecond(_ value: Double) -> String {
    guard value > 0 else { return "0 B/s" }
    return formatBytes(Int64(value)) + "/s"
}

private func formatBytes(_ value: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var amount = Double(value)
    var index = 0
    while amount >= 1024, index < units.count - 1 {
        amount /= 1024
        index += 1
    }
    return String(format: amount >= 100 ? "%.0f %@" : "%.1f %@", amount, units[index])
}
