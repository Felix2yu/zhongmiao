import SwiftUI
import ZhongmiaoCore

struct DiarumScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<DiarumSnapshot>
    @State private var showCredential = false

    // 编辑器
    @State private var selectedDate: Date = .now
    @State private var text = ""
    @State private var baseline: DiarumDiary?
    @State private var isLoadingEntry = false
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveNote: String?
    @State private var conflict = false
    @State private var pendingDate: Date?
    @State private var awaitingLogin = false

    // 搜索
    @State private var query = ""
    @State private var hits: [DiarumSearchHit] = []
    @State private var isSearching = false
    @State private var searchError: String?

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
            serviceID: "diarum",
            baseURL: baseURL,
            center: center,
            loader: {
                guard let jwt = center.credential(for: "diarum")?.jwt, !jwt.isEmpty else {
                    throw IntegrationAPIError.unauthorized
                }
                let client = DiarumClient(baseURL: baseURL, jwt: jwt)
                async let today = client.diary(date: QiansiLocalDate.dayString(.now))
                async let recent = client.recent(limit: 8)
                async let stats = client.stats()
                return DiarumSnapshot(
                    today: try await today,
                    recent: try await recent,
                    stats: try? await stats
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

            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["diarum"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            editorSection
            recentSection
            searchSection

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("在网页版写日记（媒体、AI 润色、导入导出）", systemImage: "safari")
                }
            } footer: {
                Text("原生保存只覆盖正文；情绪、场景、标签、天气保持原值。")
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存")
                    }
                }
                .disabled(!isDirty || isSaving)
                .accessibilityLabel("保存日记")
            }
            ToolbarItem(placement: .primaryAction) {
                IntegrationScreenMenu(service: service, definition: definition) {
                    Task { await store.refresh() }
                }
            }
        }
        .refreshable {
            await store.refresh()
            await loadEntry(selectedDate)
        }
        .task {
            await store.loadCache()
            await store.refreshIfNeeded()
            await loadEntry(selectedDate)
            await scheduleReminder()
        }
        .onChange(of: store.lastUpdated) { _, _ in
            Task { await scheduleReminder() }
        }
        .onChange(of: store.center.reminderRevision) {
            Task { await scheduleReminder() }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "diarum") {
            Task {
                await store.refresh()
                // 冷启动时凭据是异步登录出来的，登录完成前不要覆盖用户正在写的内容。
                if !isDirty { await loadEntry(selectedDate) }
            }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
        .confirmationDialog("这一天有未保存的修改", isPresented: Binding(
            get: { pendingDate != nil },
            set: { if !$0 { pendingDate = nil } }
        ), titleVisibility: .visible) {
            Button("放弃修改并切换", role: .destructive) {
                if let target = pendingDate {
                    pendingDate = nil
                    Task { await loadEntry(target) }
                }
            }
            Button("继续编辑", role: .cancel) { pendingDate = nil }
        } message: {
            Text("切换日期会丢掉当前正文。")
        }
        .confirmationDialog("这一天在别处被改过", isPresented: $conflict, titleVisibility: .visible) {
            Button("用我的内容覆盖", role: .destructive) {
                Task { await save(force: true) }
            }
            Button("载入服务器版本", role: .cancel) {
                Task { await loadEntry(selectedDate) }
            }
        } message: {
            Text("服务器上的正文比这里新。覆盖会丢掉那边的改动。")
        }
    }

    // MARK: - 编辑器

    private var editorSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    shiftDay(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(spacing: 2) {
                    Text(dateTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(dateSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    shiftDay(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .disabled(isTodayOrFuture)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            if isLoadingEntry {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在读取…").font(.caption).foregroundStyle(.secondary)
                }
            } else if awaitingLogin {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在登录吾身…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let loadError {
                LoadFailureView(title: "这一天的日记读不出来", detail: loadError) {
                    Task { await loadEntry(selectedDate) }
                }
            } else {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("写点什么…")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }

            HStack(spacing: 8) {
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(isDirty ? .orange : .secondary)
                Spacer()
                if let mood = baseline?.mood, mood > 0 {
                    moodTag(mood)
                }
                Text("\(text.count) 字")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
        } header: {
            Text("日记")
        } footer: {
            if let saveNote {
                Text(saveNote)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if let recent = store.snapshot?.recent, !recent.isEmpty {
            Section {
                ForEach(recent, id: \.identity) { diary in
                    Button {
                        jump(to: diary.date)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(diary.date)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if diary.date == currentDateString {
                                    CapsuleTag(text: "正在编辑", systemImage: "pencil", tint: .accentColor)
                                }
                            }
                            Text(diary.content ?? "")
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("最近日记")
            }
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜正文、标签、场景", text: $query)
                    .zmPlainTextInput()
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                if !query.isEmpty {
                    Button {
                        query = ""
                        hits = []
                        searchError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isSearching {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在搜索…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let searchError {
                Text(searchError).font(.caption).foregroundStyle(.red)
            } else if !hits.isEmpty {
                ForEach(hits) { hit in
                    Button {
                        jump(to: hit.date)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hit.date)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(hit.snippet ?? "")
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(hits.isEmpty ? "搜索" : "搜索结果 · \(hits.count)")
        }
    }

    // MARK: - 状态

    private var isDirty: Bool {
        text != (baseline?.content ?? "")
    }

    private var currentDateString: String {
        QiansiLocalDate.dayString(selectedDate)
    }

    private var isTodayOrFuture: Bool {
        Calendar.current.startOfDay(for: selectedDate) >= Calendar.current.startOfDay(for: .now)
    }

    private var dateTitle: String {
        selectedDate.formatted(.dateTime.month().day())
    }

    private var dateSubtitle: String {
        let weekday = selectedDate.formatted(.dateTime.weekday(.wide))
        if Calendar.current.isDateInToday(selectedDate) { return "今天 · \(weekday)" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "昨天 · \(weekday)" }
        return "\(selectedDate.formatted(.dateTime.year())) · \(weekday)"
    }

    private var statusText: String {
        if isSaving { return "正在保存…" }
        if let saveNote { return saveNote }
        if isDirty { return "有未保存的修改" }
        return baseline?.hasContent == true ? "已保存" : "还没有内容"
    }

    private var bannerState: IntegrationCenter.CredentialState? {
        let state = store.center.state(for: "diarum")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("连续", value: store.snapshot?.stats?.streak.map { "\($0) 天" } ?? "—", tint: .accentColor)
            metric("总篇数", value: store.snapshot?.stats?.total.map(String.init) ?? "—", tint: .blue)
            metric("最近", value: store.snapshot?.recent.first?.date ?? "—", tint: .secondary)
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

    private func moodTag(_ mood: Int) -> some View {
        let title: String
        switch mood {
        case 1: title = "很低落"
        case 2: title = "不愉快"
        case 3: title = "平静"
        case 4: title = "愉快"
        case 5: title = "很开心"
        default: title = "已记录"
        }
        return CapsuleTag(text: title, systemImage: "face.smiling", tint: .orange)
    }

    // MARK: - 数据

    private func client() -> DiarumClient? {
        guard let jwt = store.center.credential(for: "diarum")?.jwt, !jwt.isEmpty else { return nil }
        return DiarumClient(baseURL: baseURL, jwt: jwt)
    }

    private func shiftDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        switchTo(next)
    }

    private func jump(to dateString: String) {
        guard let date = parse(dateString) else { return }
        switchTo(date)
    }

    private func switchTo(_ date: Date) {
        if isDirty {
            pendingDate = date
        } else {
            Task { await loadEntry(date) }
        }
    }

    private func parse(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }

    private func loadEntry(_ date: Date) async {
        selectedDate = date
        isLoadingEntry = true
        loadError = nil
        saveNote = nil
        defer { isLoadingEntry = false }
        guard let client = client() else {
            // 冷启动的静默登录还没回来，别急着报「凭据失效」。
            baseline = nil
            text = ""
            awaitingLogin = true
            return
        }
        awaitingLogin = false
        do {
            let diary = try await client.diary(date: QiansiLocalDate.dayString(date))
            baseline = diary
            text = diary?.content ?? ""
        } catch {
            baseline = nil
            text = ""
            loadError = error.localizedDescription
            store.center.reportError(error, for: "diarum")
        }
    }

    private func save(force: Bool = false) async {
        guard let client = client(), !isSaving else { return }
        isSaving = true
        saveNote = nil
        defer { isSaving = false }
        do {
            if !force, let updated = baseline?.updated {
                let latest = try await client.diary(date: currentDateString)
                if let serverUpdated = latest?.updated, serverUpdated != updated,
                   (latest?.content ?? "") != (baseline?.content ?? "") {
                    conflict = true
                    return
                }
            }
            let saved = try await client.save(date: currentDateString, content: text)
            baseline = saved
            text = saved.content ?? text
            saveNote = "已保存 " + Date.now.formatted(.dateTime.hour().minute().second())
            store.center.markValid(serviceID: "diarum")
            await store.refresh()
        } catch {
            saveNote = "保存失败：" + error.localizedDescription
            store.center.reportError(error, for: "diarum")
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hits = []
            return
        }
        guard let client = client() else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            hits = try await client.search(trimmed)
        } catch {
            hits = []
            searchError = error.localizedDescription
        }
    }

    private func scheduleReminder() async {
        let preference = store.center.preference(for: "diarum")
        let hasEntry = store.snapshot?.today?.hasContent ?? false
        let plans = DiarumReminderPlanner.plan(
            hasEntryToday: hasEntry,
            hour: preference.reminderHour,
            minute: preference.reminderMinute
        )
        await store.center.syncReminders(serviceID: "diarum", plans: plans)
    }
}
