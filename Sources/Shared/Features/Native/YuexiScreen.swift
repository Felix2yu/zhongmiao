import SwiftUI
import ZhongmiaoCore

struct YuexiScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<YuexiSnapshot>
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
            serviceID: "yuexi",
            baseURL: baseURL,
            center: center,
            loader: {
                guard let cookie = center.credential(for: "yuexi")?.cookieHeader else {
                    throw IntegrationAPIError.unauthorized
                }
                let client = YuexiClient(baseURL: baseURL, cookie: cookie)
                async let status = client.status()
                async let anomalies = client.anomalies()
                return YuexiSnapshot(
                    status: try await status,
                    anomalies: try await anomalies
                )
            }
        ))
    }

    var body: some View {
        List {
            Section {
                countdownCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            }

            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["yuexi"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            if let status = store.snapshot?.status {
                Section {
                    ForEach(status.upcoming, id: \.nextPeriod) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "周期")
                                    .font(.subheadline)
                                Text(item.nextPeriod)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.daysLeft >= 0 ? "\(item.daysLeft) 天后" : "已到期")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(item.daysLeft <= 3 ? .orange : .secondary)
                        }
                    }
                } header: {
                    Text("近期提醒")
                } footer: {
                    Text("原生页面只显示倒计时与状态；详细记录、日记录入和导出仍在网页版。")
                }
            }

            if let anomalies = store.snapshot?.anomalies, !anomalies.isEmpty {
                Section {
                    ForEach(anomalies) { anomaly in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(anomaly.type)
                                    .font(.subheadline)
                                Spacer()
                                CapsuleTag(
                                    text: anomaly.severity == "info" ? "提示" : "注意",
                                    tint: anomaly.severity == "info" ? .blue : .orange
                                )
                            }
                            Text(anomaly.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 1)
                    }
                } header: {
                    Text("异常提示")
                }
            }

            Section {
                if let config = store.snapshot?.status?.config {
                    LabeledContent("通知", value: config.enabled == true ? "已开启" : "未开启")
                    if let days = config.daysBefore {
                        LabeledContent("提前", value: "\(days) 天")
                    }
                }
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("记录与导出", systemImage: "safari")
                }
            } header: {
                Text("设置")
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
            await scheduleReminders()
        }
        .onChange(of: store.lastUpdated) { _, _ in
            Task { await scheduleReminders() }
        }
        .onChange(of: store.center.reminderRevision) {
            Task { await scheduleReminders() }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "yuexi") {
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
        let state = store.center.state(for: "yuexi")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var countdownCard: some View {
        let next = store.snapshot?.status?.upcoming.min { $0.daysLeft < $1.daysLeft }
        return VStack(alignment: .leading, spacing: 6) {
            Text("距离下次周期")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let next {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(max(0, next.daysLeft))")
                        .font(.largeTitle.weight(.semibold).monospacedDigit())
                    Text("天")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(next.nextPeriod)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("暂无预测")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }

    private func scheduleReminders() async {
        guard let status = store.snapshot?.status else { return }
        let preference = store.center.preference(for: "yuexi")
        let inputs: [YuexiReminderInput] = status.upcoming.compactMap { item in
            guard let date = QiansiLocalDate.parse(item.nextPeriod) else { return nil }
            return YuexiReminderInput(name: item.name ?? "月汐", nextPeriod: date, daysLeft: item.daysLeft)
        }
        let plans = YuexiReminderPlanner.plan(
            upcoming: inputs,
            daysBefore: status.config?.daysBefore ?? 3,
            hour: preference.reminderHour,
            minute: preference.reminderMinute
        )
        await store.center.syncReminders(serviceID: "yuexi", plans: plans)
    }
}
