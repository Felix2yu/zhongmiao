import SwiftUI
import ZhongmiaoCore

struct MujianScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<MujianSnapshot>
    @State private var mode: Mode = .upcoming
    @State private var showCredential = false

    // 全部 / 搜索
    @State private var query = ""
    @State private var records: [MujianRecord] = []
    @State private var total = 0
    @State private var isSearching = false
    @State private var listError: String?

    // 详情与录入
    @State private var selected: MujianRecord?
    @State private var showComposer = false
    @State private var draft = MujianRecordDraft()
    @State private var categories: [MujianCategory] = []
    @State private var actionError: String?

    enum Mode: String, CaseIterable, Identifiable {
        case upcoming = "近期"
        case all = "全部"
        case stats = "统计"

        var id: String { rawValue }
    }

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
            serviceID: "mujian",
            baseURL: baseURL,
            center: center,
            loader: {
                let token = center.credential(for: "mujian")?.bearer ?? ""
                let client = MujianClient(baseURL: baseURL, token: token)
                async let dashboard = client.dashboard()
                async let upcoming = ShowClient(days: 14).fetchUpcoming(baseURL: baseURL, token: token)
                return MujianSnapshot(
                    dashboard: try? await dashboard,
                    upcoming: try await upcoming
                )
            }
        ))
    }

    var body: some View {
        List {
            if mode != .stats {
                Section {
                    metrics
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                }
            }

            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["mujian"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                Picker("视图", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            }

            switch mode {
            case .upcoming: upcomingSection
            case .all: allSection
            case .stats: statsSection
            }

            if let actionError {
                Section {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("在网页版管理（剧种、演员、场馆、备份）", systemImage: "safari")
                }
            } footer: {
                Text("录入、搜索、标记已观看已可在原生完成；演出提醒仍由既有本地通知排程。")
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await prepareComposer() }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("录入演出")
            }
            ToolbarItem(placement: .primaryAction) {
                IntegrationScreenMenu(service: service, definition: definition) {
                    Task { await store.refresh() }
                }
            }
        }
        .refreshable {
            await store.refresh()
            if mode == .all { await loadRecords(reset: true) }
        }
        .task {
            await store.loadCache()
            await store.refreshIfNeeded()
        }
        .task(id: mode) {
            if mode == .all, records.isEmpty {
                await loadRecords(reset: true)
            }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "mujian") {
            Task {
                await store.refresh()
                if mode == .all { await loadRecords(reset: true) }
            }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
        .sheet(item: $selected) { record in
            detailSheet(record)
        }
        .sheet(isPresented: $showComposer) {
            composer
        }
    }

    // MARK: - 各区

    @ViewBuilder
    private var upcomingSection: some View {
        if let upcoming = store.snapshot?.upcoming, !upcoming.isEmpty {
            Section {
                ForEach(upcoming) { show in
                    Button {
                        Task { await open(showID: show.id) }
                    } label: {
                        upcomingRow(show)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("未来 14 天")
            }
        } else {
            Section {
                EmptyStateView(
                    symbol: "theatermasks",
                    title: "近期没有演出",
                    message: "幕间里未来 14 天没有待看记录。"
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var allSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜剧目、演员、场馆、备注", text: $query)
                    .zmPlainTextInput()
                    .submitLabel(.search)
                    .onSubmit { Task { await loadRecords(reset: true) } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        Task { await loadRecords(reset: true) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if let listError {
            Section {
                LoadFailureView(title: "加载失败", detail: listError) {
                    Task { await loadRecords(reset: true) }
                }
            }
        } else if records.isEmpty {
            Section {
                if isSearching {
                    HStack {
                        ProgressView()
                        Text("正在查询…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    EmptyStateView(
                        symbol: "text.magnifyingglass",
                        title: query.isEmpty ? "还没有演出记录" : "没有匹配的演出",
                        message: query.isEmpty ? "点右上角 + 录入第一场。" : "换个关键词，或清空搜索看全部。"
                    )
                    .listRowBackground(Color.clear)
                }
            }
        } else {
            Section {
                ForEach(records) { record in
                    Button {
                        selected = record
                    } label: {
                        recordRow(record)
                    }
                    .buttonStyle(.plain)
                }
                if records.count < total {
                    Button {
                        Task { await loadRecords(reset: false) }
                    } label: {
                        HStack {
                            if isSearching { ProgressView().controlSize(.small) }
                            Text(isSearching ? "加载中…" : "加载更多（\(records.count)/\(total)）")
                                .font(.caption)
                        }
                    }
                    .disabled(isSearching)
                }
            } header: {
                Text(query.isEmpty ? "全部记录 · \(total)" : "搜索结果 · \(records.count)")
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        if let dashboard = store.snapshot?.dashboard {
            Section {
                HStack(spacing: 10) {
                    metric("总场次", value: dashboard.totalRecords.map(String.init) ?? "—", tint: .accentColor)
                    metric("城市", value: dashboard.totalCities.map(String.init) ?? "—", tint: .blue)
                    metric("平均分", value: dashboard.avgRating.map { String(format: "%.1f", $0) } ?? "—", tint: .orange)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
            }

            if let categories = dashboard.byCategory, !categories.isEmpty {
                Section {
                    ForEach(categories.prefix(8)) { item in
                        statBar(name: item.name, count: item.count, peak: categories.map(\.count).max() ?? 1, tint: .accentColor)
                    }
                } header: {
                    Text("剧种分布")
                }
            }

            if let cities = dashboard.byCity, !cities.isEmpty {
                Section {
                    ForEach(cities.prefix(6)) { item in
                        statBar(name: item.name, count: item.count, peak: cities.map(\.count).max() ?? 1, tint: .blue)
                    }
                } header: {
                    Text("城市分布")
                }
            }

            if let top = dashboard.topRated, !top.isEmpty {
                Section {
                    ForEach(top.prefix(5)) { record in
                        Button {
                            selected = record
                        } label: {
                            recordRow(record)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("高分演出")
                }
            }
        } else {
            Section {
                EmptyStateView(
                    symbol: "chart.bar",
                    title: "还没有统计数据",
                    message: "下拉刷新，或先在网页版补几场记录。"
                )
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - 行

    private func upcomingRow(_ show: Show) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(show.startsAt.formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("《\(show.name)》")
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text([show.venue, show.seat].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(show.startsAt.formatted(.dateTime.hour().minute()))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func recordRow(_ record: MujianRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if record.watched == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
                Text(recordSubtitle(record))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if let date = record.startsAt {
                    Text(date.formatted(.dateTime.year().month().day()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if let text = record.dateText, !text.isEmpty {
                    Text(text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let rating = record.rating, rating > 0 {
                    Text(String(repeating: "★", count: min(rating, 5)))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func recordSubtitle(_ record: MujianRecord) -> String {
        var parts: [String] = []
        if !record.categoryLabel.isEmpty { parts.append(record.categoryLabel) }
        if !record.venueLabel.isEmpty { parts.append(record.venueLabel) }
        if let seat = record.seat, !seat.isEmpty { parts.append(seat) }
        return parts.joined(separator: " · ")
    }

    private func statBar(name: String, count: Int, peak: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.caption)
                Spacer()
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                let ratio = peak > 0 ? CGFloat(count) / CGFloat(peak) : 0
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(tint.opacity(0.75))
                    .frame(width: Swift.max(4, proxy.size.width * ratio), height: 6)
            }
            .frame(height: 6)
        }
        .padding(.vertical, 1)
    }

    // MARK: - 详情与录入

    private func detailSheet(_ record: MujianRecord) -> some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("剧目", value: record.name)
                    if let date = record.startsAt {
                        LabeledContent("时间", value: date.formatted(.dateTime.year().month().day().hour().minute()))
                    } else if let text = record.dateText, !text.isEmpty {
                        LabeledContent("时间", value: text)
                    }
                    if !record.venueLabel.isEmpty {
                        LabeledContent("场馆", value: record.venueLabel)
                    }
                    if let seat = record.seat, !seat.isEmpty {
                        LabeledContent("座位", value: seat)
                    }
                    if let duration = record.duration, duration > 0 {
                        LabeledContent("时长", value: "\(duration) 分钟")
                    }
                    if let rating = record.rating, rating > 0 {
                        LabeledContent("评分", value: String(repeating: "★", count: min(rating, 5)))
                    }
                    if let price = record.price, price > 0 {
                        LabeledContent("票价", value: "¥\(String(format: "%.0f", price))")
                    }
                }

                if let artists = record.artistNames, !artists.isEmpty {
                    Section("演员") {
                        Text(artists.joined(separator: "、"))
                            .font(.callout)
                    }
                }

                if let remark = record.remark, !remark.isEmpty {
                    Section("备注") {
                        Text(remark)
                            .font(.callout)
                    }
                }

                Section {
                    Toggle("已观看", isOn: Binding(
                        get: { record.watched == true },
                        set: { newValue in
                            Task { await toggleWatched(record, to: newValue) }
                        }
                    ))
                } footer: {
                    Text("标记会直接写回幕间，和 CalDAV 待办的完成态同源。")
                }

                Section {
                    NavigationLink {
                        ServiceScreen(service: service, initialURL: baseURL)
                    } label: {
                        Label("在网页版编辑这场演出", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("演出详情")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { selected = nil }
                }
            }
        }
    }

    private var composer: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("剧目名称", text: $draft.name)
                        .zmPlainTextInput()
                    DatePicker("演出时间", selection: $draft.date)
                    TextField("城市", text: $draft.city)
                        .zmPlainTextInput()
                    TextField("场馆", text: $draft.venue)
                        .zmPlainTextInput()
                    TextField("座位", text: $draft.seat)
                        .zmPlainTextInput()
                }

                if !categories.isEmpty {
                    Section("剧种") {
                        ForEach(categories) { category in
                            Button {
                                toggleDraftCategory(category.name)
                            } label: {
                                HStack {
                                    Text(category.name).foregroundStyle(.primary)
                                    Spacer()
                                    if draft.categoryNames.contains(category.name) {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("可选") {
                    TextField("备注", text: $draft.remark, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("时长（分钟）", value: $draft.duration, format: .number)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                if let actionError {
                    Section {
                        Text(actionError).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("录入演出")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showComposer = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task { await saveDraft() }
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }

    // MARK: - 数据

    private var bannerState: IntegrationCenter.CredentialState? {
        let state = store.center.state(for: "mujian")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var metrics: some View {
        let dashboard = store.snapshot?.dashboard
        return HStack(spacing: 10) {
            metric("记录", value: dashboard?.totalRecords.map(String.init) ?? "—", tint: .accentColor)
            metric("城市", value: dashboard?.totalCities.map(String.init) ?? "—", tint: .blue)
            metric("评分", value: dashboard?.avgRating.map { String(format: "%.1f", $0) } ?? "—", tint: .orange)
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

    private func client() -> MujianClient {
        MujianClient(baseURL: baseURL, token: store.center.credential(for: "mujian")?.bearer ?? "")
    }

    private func loadRecords(reset: Bool) async {
        guard !isSearching else { return }
        isSearching = true
        listError = nil
        defer { isSearching = false }
        let offset = reset ? 0 : records.count
        do {
            let page = try await client().records(query: query, limit: 30, offset: offset)
            if reset {
                records = page.records
            } else {
                let known = Set(records.map(\.id))
                records += page.records.filter { !known.contains($0.id) }
            }
            total = page.total ?? records.count
            store.center.markValid(serviceID: "mujian")
        } catch {
            if reset { records = [] }
            listError = error.localizedDescription
            store.center.reportError(error, for: "mujian")
        }
    }

    private func open(showID: String) async {
        do {
            selected = try await client().record(id: showID)
        } catch {
            // 未来场次本身就来自同一份记录，取详情失败时退回列表数据即可。
            listError = error.localizedDescription
        }
    }

    private func toggleWatched(_ record: MujianRecord, to value: Bool) async {
        actionError = nil
        do {
            let updated = try await client().setWatched(id: record.id, watched: value)
            if selected?.id == updated.id { selected = updated }
            if let index = records.firstIndex(where: { $0.id == updated.id }) {
                records[index] = updated
            }
            await store.refresh()
        } catch {
            actionError = error.localizedDescription
            store.center.reportError(error, for: "mujian")
        }
    }

    private func prepareComposer() async {
        actionError = nil
        draft = MujianRecordDraft()
        if categories.isEmpty {
            categories = (try? await client().categories()) ?? []
        }
        showComposer = true
    }

    private func toggleDraftCategory(_ name: String) {
        if let index = draft.categoryNames.firstIndex(of: name) {
            draft.categoryNames.remove(at: index)
        } else {
            draft.categoryNames.append(name)
        }
    }

    private func saveDraft() async {
        actionError = nil
        do {
            let created = try await client().create(draft)
            showComposer = false
            await loadRecords(reset: true)
            await store.refresh()
            selected = created
        } catch {
            actionError = error.localizedDescription
            store.center.reportError(error, for: "mujian")
        }
    }
}
