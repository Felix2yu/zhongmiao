import SwiftUI
import ZhongmiaoCore

struct DiarumScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<DiarumSnapshot>
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
        _store = State(initialValue: IntegrationSnapshotModel(
            serviceID: "diarum",
            baseURL: baseURL,
            center: center,
            loader: {
                guard let jwt = center.credential(for: "diarum")?.jwt, !jwt.isEmpty else {
                    throw IntegrationAPIError.unauthorized
                }
                let client = DiarumClient(baseURL: baseURL, jwt: jwt)
                async let today = client.today(date: QiansiLocalDate.dayString(.now))
                async let recent = client.recent(limit: 5)
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

            Section {
                if let today = store.snapshot?.today, today.hasContent {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("今天")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let mood = today.mood, mood > 0 {
                                moodTag(mood)
                            }
                        }
                        Text(today.content ?? "")
                            .font(.subheadline)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } else {
                    EmptyStateView(
                        symbol: "square.and.pencil",
                        title: "今天还没有日记",
                        message: "原生只读展示，避免误覆盖网页版正文。写日记仍在网页版完成。"
                    )
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("今日")
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("去网页版写日记", systemImage: "square.and.pencil")
                }
            }

            if let recent = store.snapshot?.recent, !recent.isEmpty {
                Section {
                    ForEach(recent, id: \.identity) { diary in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(diary.date)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(diary.content ?? "")
                                .font(.caption)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("最近日记")
                }
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
            await scheduleReminder()
        }
        .onChange(of: store.lastUpdated) { _, _ in
            Task { await scheduleReminder() }
        }
        .onChange(of: store.center.reminderRevision) {
            Task { await scheduleReminder() }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "diarum") {
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
