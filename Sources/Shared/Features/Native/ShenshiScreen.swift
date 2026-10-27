import SwiftUI
import ZhongmiaoCore

struct ShenshiScreen: View {

    @Environment(AppModel.self) private var model
    /// 点通知进来时要直达的那条任务。
    @Environment(\.nativeTarget) private var nativeTarget

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: ShenshiModel
    @State private var showCredential = false
    /// 要滚动过去的那条任务。
    @State private var focusID: String?

    init(
        service: ServiceDefinition,
        baseURL: URL,
        definition: IntegrationDefinition,
        center: IntegrationCenter
    ) {
        self.service = service
        self.baseURL = baseURL
        self.definition = definition
        _store = State(initialValue: ShenshiModel(service: service, baseURL: baseURL, center: center))
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
                            error: store.error ?? store.center.lastErrors["shenshi"],
                            onConfigure: { showCredential = true },
                            onRetry: { Task { await store.refresh() } }
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }

                taskSection("今天", tasks: store.snapshot?.today ?? [])
                taskSection("逾期", tasks: store.snapshot?.overdue ?? [], highlight: true)

                if let habits = store.snapshot?.habits, !habits.isEmpty {
                    Section {
                        ForEach(habits) { habit in
                            habitRow(habit)
                        }
                    } header: {
                        Text("习惯")
                    }
                }

            if let reminders = store.snapshot?.reminders, !reminders.isEmpty {
                Section {
                    ForEach(reminders, id: \.ackId) { hit in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hit.task.title)
                                .font(.subheadline)
                            HStack(spacing: 6) {
                                if let label = hit.dueLabel {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(hit.overdue == true ? .red : .secondary)
                                }
                                if let fire = ShenshiDate.parse(hit.fireAt) {
                                    Text(fire.formatted(.dateTime.month().day().hour().minute()))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 1)
                        .id("task:\(hit.task.id)")
                    }
                } header: {
                    Text("到期提醒")
                }
            }

            Section {
                NavigationLink {
                    ServiceScreen(service: service, initialURL: baseURL)
                } label: {
                    Label("完整任务与项目管理", systemImage: "safari")
                }
            } footer: {
                Text("原生只做查看、完成与习惯打卡；任务编辑、复盘和 CalDAV 仍在网页版。")
            }
            }
            .onChange(of: focusID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
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
        .refreshWhenIntegrationReady(center: store.center, serviceID: "shenshi") {
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
        let state = store.center.state(for: "shenshi")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    /// 点通知进来时展开并滚到那条任务。
    private func focusTarget() {
        guard let target = nativeTarget, target.kind == "task" else { return }
        guard let taskID = Int64(target.identifier) else { return }
        let snapshot = store.snapshot
        let listed = (snapshot?.today ?? []) + (snapshot?.overdue ?? [])
        guard listed.contains(where: { $0.id == taskID }) else { return }
        store.expandedTaskID = taskID
        focusID = "task:\(taskID)"
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("待办", value: store.snapshot?.stats?.totalOpen ?? store.snapshot?.today.count ?? 0, tint: .accentColor)
            metric("逾期", value: store.snapshot?.stats?.overdue ?? store.snapshot?.overdue.count ?? 0, tint: .red)
            metric("连续", value: store.snapshot?.stats?.streakDays ?? 0, tint: .orange)
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

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [ShenshiTask], highlight: Bool = false) -> some View {        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    taskRow(task)
                        .id("task:\(task.id)")
                }
            } header: {
                HStack(spacing: 5) {
                    if highlight { Circle().fill(Color.red).frame(width: 6, height: 6) }
                    Text(title)
                }
            }
        }
    }

    private func taskRow(_ task: ShenshiTask) -> some View {
        let expanded = store.expandedTaskID == task.id
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    Task { await store.complete(task, completed: !task.isDone) }
                } label: {
                    if store.busyTaskIDs.contains(task.id) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(task.isDone ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.expandedTaskID = expanded ? nil : task.id
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.subheadline)
                            .strikethrough(task.isDone)
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                        HStack(spacing: 6) {
                            if let due = task.dueDate {
                                Text(due + (task.dueTime.map { " \($0)" } ?? ""))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let list = task.listName {
                                Text(list)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if let priority = task.priority, priority > 0 {
                                CapsuleTag(text: priorityTitle(priority), tint: .orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let notes = task.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let done = task.subtaskDone, let open = task.subtaskOpen, done + open > 0 {
                        Text("子任务：\(done)/\(done + open)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 34)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private func habitRow(_ habit: ShenshiHabit) -> some View {
        let stat = store.habitStat(for: habit.id)
        return HStack(spacing: 10) {
            Button {
                Task { await store.check(habit) }
            } label: {
                if store.busyHabitIDs.contains(habit.id) {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: (stat?.today ?? 0) > 0 ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle((stat?.today ?? 0) > 0 ? .green : .secondary)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    if let streak = stat?.streak, streak > 0 {
                        Text("连续 \(streak) 天")
                    }
                    if let today = stat?.today, today > 0 {
                        Text("今天 \(today)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private func priorityTitle(_ priority: Int) -> String {
        switch priority {
        case 3: "高"
        case 2: "中"
        default: "低"
        }
    }
}
