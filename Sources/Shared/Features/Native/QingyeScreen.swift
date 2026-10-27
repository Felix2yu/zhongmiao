import SwiftUI
import ZhongmiaoCore

struct QingyeScreen: View {

    @Environment(AppModel.self) private var model
    /// 点通知进来时要定位到的那一天。
    @Environment(\.nativeTarget) private var nativeTarget

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: QingyeModel
    @State private var showCredential = false
    /// 点通知进来时要定位到的分组（「今天」「明天」…）。
    @State private var focusSection: String?

    init(
        service: ServiceDefinition,
        baseURL: URL,
        definition: IntegrationDefinition,
        center: IntegrationCenter
    ) {
        self.service = service
        self.baseURL = baseURL
        self.definition = definition
        _store = State(initialValue: QingyeModel(service: service, baseURL: baseURL, center: center))
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    metrics
                        .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                }

                if let state = bannerState {
                    Section {
                        IntegrationStatusBanner(
                            state: state,
                            error: store.error ?? store.center.lastErrors["qingye"],
                            onConfigure: { showCredential = true },
                            onRetry: { Task { await store.refresh() } }
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    roomChips
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }

                if store.snapshot == nil && store.isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在读取青野…").foregroundStyle(.secondary)
                        }
                    }
                }

                if store.snapshot != nil {
                    taskSections
                    plantSections
                }
            }
            .onChange(of: focusSection) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .top)
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
        .task(id: nativeTarget?.identifier) {
            await store.loadCache()
            await store.refreshIfNeeded()
            focusTarget()
        }
        .onChange(of: store.center.reminderRevision) {
            Task { await store.rescheduleReminders() }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "qingye") {
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
        let state = store.center.state(for: "qingye")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    /// 点通知进来时定位到那一天的养护分组。
    private func focusTarget() {
        guard let target = nativeTarget, target.kind == "care" else { return }
        guard let day = QiansiLocalDate.parse(target.identifier) else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        let targetDay = calendar.startOfDay(for: day)
        store.focusDate = targetDay
        if targetDay < today {
            focusSection = "逾期"
        } else if targetDay == today {
            focusSection = "今天"
        } else if targetDay == tomorrow {
            focusSection = "明天"
        } else {
            // 更远的日期会单独列一组，放在最上面，不用滚。
            focusSection = nil
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("今日", value: store.todayTasks.count, tint: .accentColor)
            metric("逾期", value: store.overdueTasks.count, tint: .red)
            metric("植物", value: store.plantCount, tint: .green)
        }
    }

    private func metric(_ title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var roomChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "全部", selected: store.selectedRoomID == nil) {
                    store.selectedRoomID = nil
                }
                ForEach(store.rooms) { room in
                    chip(title: room.name, selected: store.selectedRoomID == room.id) {
                        store.selectedRoomID = store.selectedRoomID == room.id ? nil : room.id
                    }
                }
            }
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var taskSections: some View {
        if !store.focusTasks.isEmpty {
            taskSection(store.focusDayLabel, tasks: store.focusTasks, focused: true)
        }
        taskSection("逾期", tasks: store.overdueTasks, highlight: true)
        taskSection("今天", tasks: store.todayTasks, focused: focusSection == "今天")
        taskSection("明天", tasks: store.tomorrowTasks, focused: focusSection == "明天")
        taskSection("以后", tasks: store.laterTasks, focused: focusSection == "以后")
    }

    @ViewBuilder
    private func taskSection(
        _ title: String,
        tasks: [QingyeTask],
        highlight: Bool = false,
        focused: Bool = false
    ) -> some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    QingyeTaskRow(
                        task: task,
                        expanded: store.expandedTaskID == task.id,
                        busy: store.busyTaskIDs.contains(task.id),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.expandedTaskID = store.expandedTaskID == task.id ? nil : task.id
                            }
                        },
                        onComplete: { note in
                            Task { await store.complete(task, note: note) }
                        },
                        onPostpone: { days, note in
                            Task { await store.postpone(task, days: days, note: note) }
                        }
                    )
                }
            } header: {
                HStack(spacing: 5) {
                    if highlight { Circle().fill(Color.red).frame(width: 6, height: 6) }
                    Text(title).fontWeight(focused ? .semibold : .regular)
                    if focused {
                        Image(systemName: "scope")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .id(title)
        }
    }

    @ViewBuilder
    private var plantSections: some View {
        ForEach(Array(store.roomGroups.enumerated()), id: \.offset) { _, group in
            Section {
                ForEach(group.plants) { plant in
                    QingyePlantRow(
                        plant: plant,
                        tasks: store.tasks(for: plant.id),
                        logs: store.logs(for: plant.id),
                        expanded: store.expandedPlantID == plant.id,
                        busy: store.busyPlantIDs.contains(plant.id),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.expandedPlantID = store.expandedPlantID == plant.id ? nil : plant.id
                            }
                        },
                        onCare: { type, title in
                            Task { await store.recordCare(plant: plant, type: type, title: title) }
                        }
                    )
                }
            } header: {
                Text(group.room?.name ?? "未分房")
            }
        }
    }
}

private struct QingyeTaskRow: View {

    let task: QingyeTask
    let expanded: Bool
    let busy: Bool
    let onToggle: () -> Void
    let onComplete: (String) -> Void
    let onPostpone: (Int, String) -> Void

    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: task.typeSymbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.plant?.name ?? "植物")
                            .font(.subheadline.weight(.medium))
                        Text("\(task.title) · \(task.intervalDays) 天")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 6)

                    Text(QingyeDue.label(task.nextDue))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(task.nextDue < Calendar.current.startOfDay(for: .now) ? .red : .secondary)

                    if busy {
                        ProgressView().controlSize(.mini)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    if let last = task.lastDoneAt {
                        Text("上次：\(last.formatted(.dateTime.month().day()))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    TextField("备注（可选）", text: $note)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button("完成") {
                            onComplete(note)
                            note = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("推迟 1 天") { onPostpone(1, note) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        Button("推迟 3 天") { onPostpone(3, note) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.leading, 32)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct QingyePlantRow: View {

    let plant: QingyePlant
    let tasks: [QingyeTask]
    let logs: [QingyeCareLog]
    let expanded: Bool
    let busy: Bool
    let onToggle: () -> Void
    let onCare: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plant.name)
                            .font(.subheadline)
                        Text(plant.species.flatMap { $0.isEmpty ? nil : $0 } ?? plant.location ?? "植物")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text("\(tasks.count) 项")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    if let location = plant.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let light = plant.lightReq, !light.isEmpty {
                        Label(light, systemImage: "sun.max")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !tasks.isEmpty {
                        Text("待办：" + tasks.map(\.title).joined(separator: "、"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !logs.isEmpty {
                        Text("最近：" + logs.map { "\($0.title) \($0.at.formatted(.dateTime.month().day()))" }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 8) {
                        Button("浇水") { onCare("water", "浇水") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("施肥") { onCare("fertilize", "施肥") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .padding(.leading, 32)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }
}

private enum QingyeDue {
    static func label(_ date: Date) -> String {
        let days = QiansiLocalDate.daysUntil(date)
        return switch days {
        case ..<0: "逾期 \(-days) 天"
        case 0: "今天"
        case 1: "明天"
        default: "\(days) 天后"
        }
    }
}
