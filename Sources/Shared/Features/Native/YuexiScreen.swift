import SwiftUI
import ZhongmiaoCore

struct YuexiScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: IntegrationSnapshotModel<YuexiSnapshot>
    @State private var showCredential = false
    @State private var showRecordSheet = false
    @State private var showPersonSheet = false
    /// 写操作的错误。静默吞掉会变成「点了没反应」。
    @State private var actionError: String?

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
                // 冷启动时静默登录可能还没回来。先自己登一次，
                // 别把「还没登录」当成「凭据已失效」抛出去。
                var cookie = center.credential(for: "yuexi")?.cookieHeader
                if cookie == nil {
                    await center.reauthenticateIfPossible(serviceID: "yuexi", baseURL: baseURL)
                    cookie = center.credential(for: "yuexi")?.cookieHeader
                }
                guard let cookie else {
                    throw IntegrationAPIError.unauthorized
                }
                let client = YuexiClient(baseURL: baseURL, cookie: cookie)
                let now = Date()
                let calendar = Calendar.current
                async let status = client.status()
                async let anomalies = client.anomalies()
                async let records = client.records(
                    year: calendar.component(.year, from: now),
                    month: calendar.component(.month, from: now)
                )
                return YuexiSnapshot(
                    status: try await status,
                    anomalies: try await anomalies,
                    records: try await records
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

            if let actionError {
                Section {
                    Text(actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let records = store.snapshot?.records, !records.records.isEmpty {
                Section {
                    ForEach(records.records.sorted { $0.startDate > $1.startDate }) { record in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.startDate)
                                    .font(.subheadline.monospacedDigit())
                                if !record.note.isEmpty {
                                    Text(record.note)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let end = record.endDate, !end.isEmpty {
                                Text("至 \(end)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else {
                                CapsuleTag(text: "进行中", tint: .orange)
                            }
                        }
                    }
                } header: {
                    Text("记录历史")
                } footer: {
                    Text("只显示本月记录；跨月查询、统计与导出仍在网页版。")
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
                Button {
                    // 还没有记录人时，先把人建出来，否则记经期没有归属。
                    if persons.isEmpty {
                        showPersonSheet = true
                    } else {
                        showRecordSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(persons.isEmpty ? "添加记录人" : "记一次经期")
            }
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
        .sheet(isPresented: $showRecordSheet) {
            YuexiRecordSheet(persons: store.snapshot?.records?.persons ?? []) { personID, start, end, note in
                await createRecord(personID: personID, start: start, end: end, note: note)
            }
        }
        .sheet(isPresented: $showPersonSheet) {
            YuexiPersonSheet { name, cycle, period in
                await createPerson(name: name, cycleLength: cycle, periodLength: period)
            }
        }
    }

    private var persons: [YuexiPerson] {
        store.snapshot?.records?.persons ?? []
    }

    private func createPerson(name: String, cycleLength: Int, periodLength: Int) async {
        guard let cookie = store.center.credential(for: "yuexi")?.cookieHeader else { return }
        do {
            try await YuexiClient(baseURL: baseURL, cookie: cookie).createPerson(
                name: name,
                cycleLength: cycleLength,
                periodLength: periodLength
            )
            await store.refresh()
        } catch {
            store.center.reportError(error, for: "yuexi")
        }
    }

    private func createRecord(personID: Int64?, start: Date, end: Date?, note: String) async {
        guard let personID else {
            actionError = "没有选中记录人。"
            return
        }
        guard let cookie = store.center.credential(for: "yuexi")?.cookieHeader else {
            actionError = "尚未连接月汐，请先在设置里配置凭据。"
            return
        }
        do {
            try await YuexiClient(baseURL: baseURL, cookie: cookie).createRecord(
                personID: personID,
                startDate: Self.dayString(start),
                endDate: end.map(Self.dayString),
                note: note
            )
            actionError = nil
            await store.refresh()
        } catch {
            // 写操作的失败必须让人看见，静默吞掉会变成「点了没反应」。
            actionError = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            store.center.reportError(error, for: "yuexi")
        }
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

/// 添加记录人。
private struct YuexiPersonSheet: View {

    @Environment(\.dismiss) private var dismiss

    let onSubmit: (String, Int, Int) async -> Void

    @State private var name = ""
    @State private var cycleLength = 28
    @State private var periodLength = 5
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("记录人") {
                    TextField("名字", text: $name)
                        .accessibilityIdentifier("yuexi.personName")
                }
                Section("周期") {
                    Stepper("周期 \(cycleLength) 天", value: $cycleLength, in: 15...60)
                    Stepper("经期 \(periodLength) 天", value: $periodLength, in: 1...14)
                }
            }
            .navigationTitle("添加记录人")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        isSaving = true
                        Task {
                            await onSubmit(value, cycleLength, periodLength)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// 记一次经期。
private struct YuexiRecordSheet: View {

    @Environment(\.dismiss) private var dismiss

    let persons: [YuexiPerson]
    let onSubmit: (Int64?, Date, Date?, String) async -> Void

    @State private var personID: Int64?
    @State private var start = Date()
    @State private var ended = false
    @State private var end = Date()
    @State private var note = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("谁") {
                    Picker("记录人", selection: $personID) {
                        Text("请选择").tag(nil as Int64?)
                        ForEach(persons) { person in
                            Text(person.name).tag(person.id as Int64?)
                        }
                    }
                }

                Section("时间") {
                    DatePicker("开始", selection: $start, displayedComponents: .date)
                    Toggle("已经结束", isOn: $ended)
                    if ended {
                        DatePicker("结束", selection: $end, displayedComponents: .date)
                    }
                }

                Section("备注") {
                    TextField("备注（可留空）", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("记一次经期")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                selectDefaultPerson()
            }
            .onChange(of: persons) { _, _ in
                // 冷启动时快照可能还没加载完，列表后到时要补上默认选中，
                // 否则保存按钮一直是禁用的，点下去没反应。
                selectDefaultPerson()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        isSaving = true
                        Task {
                            await onSubmit(personID, start, ended ? end : nil, note)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || personID == nil)
                }
            }
        }
    }

    /// 默认选中第一个人，省得每次都要展开 Picker。
    private func selectDefaultPerson() {
        if personID == nil {
            personID = persons.first?.id
        }
    }
}
