import SwiftUI
import ZhongmiaoCore

struct BiliHistoryScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<BiliHistorySnapshot>
    /// 搜索关键词。非空时列表切到搜索结果。
    @State private var query = ""
    @State private var searchResults: [BiliHistoryRecord] = []
    @State private var searchTotal: Int64 = 0
    @State private var searchPage = 1
    @State private var isSearching = false
    @State private var searchError: String?
    /// 主分类，用于筛选「最近观看」。
    @State private var categories: [BiliMainCategory] = []
    @State private var selectedCategory: String?
    @State private var filteredRecords: [BiliHistoryRecord] = []

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

            Section {
                IntegrationSearchField(
                    text: $query,
                    placeholder: "搜索标题或 UP 主",
                    onSubmit: { Task { await runSearch(reset: true) } },
                    onChange: { Task { await runSearch(reset: true) } }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }

            if !categories.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            categoryChip(title: "全部", name: nil)
                            ForEach(categories.prefix(12)) { category in
                                categoryChip(title: category.name, name: category.name)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                } header: {
                    Text("按主分类筛选")
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

            if isSearching {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在搜索…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if let searchError {
                Section {
                    Text(searchError).font(.caption).foregroundStyle(.red)
                }
            } else if !query.isEmpty {
                Section {
                    if searchResults.isEmpty {
                        EmptyStateView(
                            symbol: "magnifyingglass",
                            title: "没有匹配的视频",
                            message: "换个关键词试试。"
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(searchResults) { record in
                            recordRow(record)
                        }
                        if searchResults.count < Int(searchTotal) {
                            Button {
                                Task { await loadMore() }
                            } label: {
                                Label("加载更多", systemImage: "arrow.down.circle")
                                    .font(.caption)
                            }
                            .disabled(isSearching)
                        }
                    }
                } header: {
                    Text("搜索结果 \(searchResults.count) / \(searchTotal)")
                }
            } else if !filteredRecords.isEmpty {
                Section {
                    ForEach(filteredRecords) { record in
                        recordRow(record)
                    }
                } header: {
                    Text(selectedCategory.map { "「\($0)」的观看记录" } ?? "最近观看")
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
            filteredRecords = store.snapshot?.records ?? []
            await loadCategories()
        }
        .onChange(of: store.lastUpdated) { _, _ in
            if query.isEmpty {
                Task { await applyCategory() }
            }
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

    private func recordRow(_ record: BiliHistoryRecord) -> some View {
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

    private func categoryChip(title: String, name: String?) -> some View {
        let selected = selectedCategory == name
        return Button {
            selectedCategory = name
            Task { await applyCategory() }
        } label: {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(
                    selected ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 搜索与筛选

    private func runSearch(reset: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchTotal = 0
            searchError = nil
            return
        }
        if reset {
            searchPage = 1
            searchResults = []
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let page = try await BiliHistoryClient(baseURL: baseURL).search(
                query: trimmed,
                page: searchPage,
                size: 30
            )
            searchResults = reset ? page.records : searchResults + page.records
            searchTotal = page.total ?? Int64(searchResults.count)
        } catch {
            searchError = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
        }
    }

    private func loadMore() async {
        searchPage += 1
        await runSearch(reset: false)
    }

    private func applyCategory() async {
        let client = BiliHistoryClient(baseURL: baseURL)
        do {
            if let selectedCategory {
                // 分类筛选走列表接口：它支持 main_category，搜索接口不支持。
                let data = try await client.records(mainCategory: selectedCategory, size: 60)
                filteredRecords = data
            } else {
                filteredRecords = store.snapshot?.records ?? []
            }
        } catch {
            searchError = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            filteredRecords = store.snapshot?.records ?? []
        }
    }

    private func loadCategories() async {
        guard categories.isEmpty else { return }
        if let loaded = try? await BiliHistoryClient(baseURL: baseURL).mainCategories() {
            categories = loaded
        }
    }
}
