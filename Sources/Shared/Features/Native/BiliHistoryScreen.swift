import SwiftUI
import ZhongmiaoCore

struct BiliHistoryScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<BiliHistorySnapshot>

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
            serviceID: "bili-history",
            baseURL: baseURL,
            center: center,
            loader: {
                let client = BiliHistoryClient(baseURL: baseURL)
                async let daily = client.dailyCount()
                async let records = client.recentRecords()
                async let monthly = client.monthlyStats()
                return BiliHistorySnapshot(
                    daily: try? await daily,
                    records: try await records,
                    monthly: try? await monthly
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
                        state: store.center.state(for: "bili-history"),
                        error: error,
                        onConfigure: {},
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            if let tags = store.snapshot?.monthly?.tagRanking, !tags.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(tags.prefix(8).enumerated()), id: \.offset) { _, tag in
                                CapsuleTag(text: "\(tag.tagName ?? "标签") \(tag.count ?? 0)", tint: .pink)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                } header: {
                    Text("本月偏好")
                }
            }

            if let records = store.snapshot?.records, !records.isEmpty {
                Section {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(record.title)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                Spacer(minLength: 6)
                                if record.isCompleted {
                                    CapsuleTag(text: "看完", tint: .green)
                                }
                            }
                            HStack(spacing: 8) {
                                if let author = record.authorName, !author.isEmpty {
                                    Text(author)
                                }
                                if let date = record.watchedDate {
                                    Text(date.formatted(.dateTime.month().day().hour().minute()))
                                }
                                if let duration = record.duration, duration > 0 {
                                    Text("\(duration / 60) 分钟")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    Text("最近观看")
                }
            } else {
                Section {
                    EmptyStateView(
                        symbol: "play.rectangle",
                        title: "还没有观看记录",
                        message: "拾帧集同步 Bilibili 历史后会显示在这里。"
                    )
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("搜索、导出与详情", systemImage: "safari")
                }
            } footer: {
                Text("原生看板只取小分页，避免报告类大响应；完整历史仍在网页版。")
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
    }

    private var metrics: some View {
        let daily = store.snapshot?.daily
        let monthly = store.snapshot?.monthly
        return HStack(spacing: 10) {
            metric("今日", value: daily?.totalCount.map(String.init) ?? "—", tint: .accentColor)
            metric("今日时长", value: watchTime(daily?.totalWatchSeconds ?? 0), tint: .blue)
            metric("本月视频", value: monthly?.totalVideos.map(String.init) ?? "—", tint: .pink)
        }
    }

    private func metric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func watchTime(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }
}
