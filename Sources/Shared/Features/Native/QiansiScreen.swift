import SwiftUI
import ZhongmiaoCore

struct QiansiScreen: View {

    @Environment(AppModel.self) private var model
    /// 点通知进来时要直达的那条（纪念日 / 约会 / 提醒）。
    @Environment(\.nativeTarget) private var nativeTarget

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: QiansiModel
    @State private var showCredential = false
    @State private var showAnniversarySheet = false
    @State private var showEventSheet = false
    /// 要编辑的纪念日。
    @State private var editTarget: QiansiEditTarget?
    /// 待确认归档的条目。
    @State private var archiveTarget: QiansiArchiveTarget?
    /// 要滚动过去的议程项 id。
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
        _store = State(initialValue: QiansiModel(service: service, baseURL: baseURL, center: center))
    }

    var body: some View {
        @Bindable var store = store

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
                            error: store.error ?? store.center.lastErrors["qiansi"],
                            onConfigure: { showCredential = true },
                            onRetry: { Task { await store.refresh() } }
                        )
                        .listRowInsets(EdgeInsets())
                    }
                }

                Section {
                    filterChips
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }

                if store.filter == .contacts {
                    contactsSection
                } else {
                    agendaSection
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
        .searchable(text: $store.searchText, prompt: "搜索联系人")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAnniversarySheet = true
                    } label: {
                        Label("新建纪念日", systemImage: "birthday.cake")
                    }
                    Button {
                        showEventSheet = true
                    } label: {
                        Label("新建约会", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建")
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
        .task(id: nativeTarget?.identifier) {
            await store.loadCache()
            await store.refreshIfNeeded()
            focusTarget()
        }
        .task(id: store.searchText) {
            await store.searchPeople()
        }
        .onChange(of: store.center.reminderRevision) {
            Task { await store.rescheduleReminders() }
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "qiansi") {
            Task { await store.refresh() }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
        .sheet(isPresented: $showAnniversarySheet) {
            QiansiAnniversarySheet(store: store)
        }
        .sheet(isPresented: $showEventSheet) {
            QiansiEventSheet(store: store)
        }
        .sheet(item: $editTarget) { target in
            if let original = store.anniversary(id: target.rawID) {
                QiansiEditAnniversarySheet(store: store, original: original)
            }
        }
        .confirmationDialog(
            archiveTarget.map { "归档「\($0.title)」？" } ?? "归档",
            isPresented: Binding(
                get: { archiveTarget != nil },
                set: { if !$0 { archiveTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("归档", role: .destructive) {
                guard let target = archiveTarget else { return }
                Task {
                    if target.kind == .anniversary {
                        _ = await store.archiveAnniversary(id: target.rawID)
                    } else {
                        _ = await store.archiveEvent(id: target.rawID)
                    }
                    archiveTarget = nil
                }
            }
            Button("取消", role: .cancel) {
                archiveTarget = nil
            }
        }
    }

    private var bannerState: IntegrationCenter.CredentialState? {
        let state = store.center.state(for: "qiansi")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    /// 点通知进来时把对应那条展开并滚到它。
    /// 议程项的 id 就是 `kind:原 id`，与提醒里带的目标准确对应。
    private func focusTarget() {
        guard let target = nativeTarget else { return }
        let itemID = "\(target.kind):\(target.identifier)"
        // 目标可能被当前筛选挡在外面（筛的是生日，目标却是约会），先切到全部。
        if !store.filteredAgenda.contains(where: { $0.id == itemID }), store.filter != .reminders {
            store.filter = .reminders
        }
        guard store.filteredAgenda.contains(where: { $0.id == itemID }) else { return }
        store.expandedID = itemID
        focusID = itemID
    }

    /// 提醒是「完成」，不是归档；纪念日与约会可以归档。
    private func archiveAction(for item: QiansiAgendaItem) -> (() -> Void)? {
        switch item.kind {
        case .anniversary:
            return {
                archiveTarget = QiansiArchiveTarget(kind: .anniversary, rawID: item.rawID, title: item.title)
            }
        case .event:
            return {
                archiveTarget = QiansiArchiveTarget(kind: .event, rawID: item.rawID, title: item.title)
            }
        case .reminder:
            return nil
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            metric("今日", value: store.dueTodayCount, tint: .accentColor)
            metric("未来 7 天", value: store.next7Count, tint: .orange)
            metric("联系人", value: store.peopleCount, tint: .purple)
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

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QiansiModel.Filter.allCases) { filter in
                    Button {
                        store.filter = filter
                    } label: {
                        Text(filter.title)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 11)
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

    @ViewBuilder
    private var agendaSection: some View {
        if store.filteredAgenda.isEmpty {
            Section {
                EmptyStateView(
                    symbol: "calendar.badge.clock",
                    title: "这段时间没有安排",
                    message: "新建纪念日或约会，提醒会按应用设置里的时刻排程。"
                )
                .listRowBackground(Color.clear)
            }
        } else {
            ForEach(Array(store.agendaGroups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.items) { item in
                        QiansiAgendaRow(
                            item: item,
                            expanded: store.expandedID == item.id,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    store.expandedID = store.expandedID == item.id ? nil : item.id
                                }
                            },
                            onComplete: {
                                guard let reminderID = item.reminderID else { return }
                                Task { await store.complete(reminderID: reminderID) }
                            },
                            onEdit: item.kind == .anniversary ? {
                                editTarget = QiansiEditTarget(rawID: item.rawID)
                            } : nil,
                            onArchive: archiveAction(for: item)
                        )
                        .id(item.id)
                    }
                } header: {
                    Text(dayLabel(group.day))
                }
            }
        }
    }

    @ViewBuilder
    private var contactsSection: some View {
        if store.people.isEmpty {
            Section {
                EmptyStateView(
                    symbol: "person.2",
                    title: "没有联系人",
                    message: "牵丝里还没有人物记录，或当前搜索没有结果。"
                )
                .listRowBackground(Color.clear)
            }
        } else {
            Section {
                ForEach(store.people) { person in
                    QiansiPersonRow(
                        person: person,
                        expanded: store.expandedID == person.id,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                store.expandedID = store.expandedID == person.id ? nil : person.id
                            }
                        }
                    )
                }
            } header: {
                Text("联系人")
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天 · \(date.formatted(.dateTime.month().day()))" }
        if calendar.isDateInTomorrow(date) { return "明天 · \(date.formatted(.dateTime.month().day()))" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
}

private struct QiansiAgendaRow: View {

    let item: QiansiAgendaItem
    let expanded: Bool
    let onToggle: () -> Void
    let onComplete: () -> Void
    /// 编辑（目前只有纪念日可改）。
    let onEdit: (() -> Void)?
    /// 归档。
    let onArchive: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: item.kind.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.medium))
                        Text(item.subtitle.isEmpty ? item.kind.title : item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(remainingLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(item.daysUntil == 0 ? .orange : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        item.date.formatted(.dateTime.year().month().day().weekday(.abbreviated)),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if item.kind == .reminder, item.reminderID != nil {
                        Button("完成提醒") {
                            onComplete()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if onEdit != nil || onArchive != nil {
                        HStack(spacing: 8) {
                            if let onEdit {
                                Button("编辑", action: onEdit)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                            if let onArchive {
                                Button("归档", action: onArchive)
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .tint(.orange)
                            }
                        }
                    }
                }
                .padding(.leading, 32)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch item.kind {
        case .anniversary: .pink
        case .event: .blue
        case .reminder: .orange
        }
    }

    private var remainingLabel: String {
        guard let days = item.daysUntil else { return item.kind.title }
        return switch days {
        case ..<0: "已过"
        case 0: "今天"
        case 1: "明天"
        default: "\(days) 天后"
        }
    }
}

private struct QiansiPersonRow: View {

    let person: QiansiPerson
    let expanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(.purple)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.subheadline.weight(.medium))
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if let grade = person.grade {
                        CapsuleTag(text: gradeTitle(grade), tint: .purple)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 7) {
                    if let phone = person.phone, !phone.isEmpty {
                        HStack(spacing: 10) {
                            Label(phone, systemImage: "phone")
                                .font(.caption)
                            Button("拨打") { call(phone) }
                                .buttonStyle(.borderless)
                                .font(.caption.weight(.semibold))
                            Button("复制") {
                                Pasteboard.copy(phone)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    if let birthday = person.birthday, !birthday.isEmpty {
                        Label(
                            birthday + (person.birthdayIsLunar == true ? " · 农历" : ""),
                            systemImage: "birthday.cake"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let last = person.stats?.lastContact, !last.isEmpty {
                        Label("上次联系：\(last)", systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let meetings = person.stats?.meetingCount {
                        Label("见面 \(meetings) 次", systemImage: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let notes = person.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                    }
                }
                .padding(.leading, 34)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        [
            person.nickname,
            person.location,
            person.phone
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func gradeTitle(_ grade: Int) -> String {
        return switch grade {
        case 5: "至交"
        case 4: "好友"
        case 3: "常联系"
        case 2: "认识"
        case 1: "点头之交"
        default: "弱联系"
        }
    }

    private func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel:\(digits)") else { return }
        Platform.openExternally(url)
    }
}

private struct QiansiAnniversarySheet: View {

    @Environment(\.dismiss) private var dismiss
    let store: QiansiModel

    @State private var title = ""
    @State private var date = Date()
    @State private var personID: String?
    @State private var isLunar = false
    @State private var repeatYearly = true
    @State private var remindDays: Set<Int> = [7, 3, 1, 0]
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（如：妈妈生日）", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("关联联系人", selection: $personID) {
                        Text("不关联").tag(nil as String?)
                        ForEach(store.snapshot?.people ?? []) { person in
                            Text(person.name).tag(person.id as String?)
                        }
                    }
                    Toggle("农历", isOn: $isLunar)
                    Toggle("每年重复", isOn: $repeatYearly)
                } header: {
                    Text("纪念日")
                }

                Section {
                    HStack(spacing: 7) {
                        ForEach([0, 1, 3, 7], id: \.self) { day in
                            Button {
                                if remindDays.contains(day) {
                                    remindDays.remove(day)
                                } else {
                                    remindDays.insert(day)
                                }
                            } label: {
                                Text(day == 0 ? "当天" : "\(day) 天前")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(remindDays.contains(day) ? Color.white : Color.secondary)
                                    .background(
                                        remindDays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("提前提醒")
                } footer: {
                    Text("按应用设置里的全局时刻投递本地通知。")
                }

                if let error {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新建纪念日")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        let ok = await store.createAnniversary(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            personID: personID,
            isLunar: isLunar,
            repeatYearly: repeatYearly,
            remindDays: remindDays.sorted()
        )
        isSaving = false
        if ok {
            dismiss()
        } else {
            error = store.error ?? "保存失败"
        }
    }
}

/// 要编辑的纪念日。
struct QiansiEditTarget: Identifiable {
    let rawID: String
    var id: String { rawID }
}

/// 待归档的条目。
struct QiansiArchiveTarget: Identifiable {
    enum Kind: String {
        case anniversary
        case event
    }
    let kind: Kind
    let rawID: String
    let title: String
    var id: String { "\(kind.rawValue):\(rawID)" }
}

/// 编辑已有的纪念日。
///
/// 服务端的 UPDATE 是全量覆盖（不改的列会被写空），所以这里按原始记录回写，
/// 只把用户真正改过的字段换掉。
private struct QiansiEditAnniversarySheet: View {

    @Environment(\.dismiss) private var dismiss

    let store: QiansiModel
    let original: QiansiAnniversary

    @State private var title: String
    @State private var date: Date
    @State private var personID: String?
    @State private var isLunar: Bool
    @State private var repeatYearly: Bool
    @State private var remindDays: Set<Int>
    @State private var isSaving = false
    @State private var error: String?

    init(store: QiansiModel, original: QiansiAnniversary) {
        self.store = store
        self.original = original
        _title = State(initialValue: original.title)
        _date = State(initialValue: QiansiLocalDate.parse(original.date) ?? .now)
        _personID = State(initialValue: original.personId)
        _isLunar = State(initialValue: original.isLunar ?? false)
        _repeatYearly = State(initialValue: original.repeatYearly ?? true)
        _remindDays = State(initialValue: Set(
            (original.remindDays ?? "")
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（如：妈妈生日）", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("关联联系人", selection: $personID) {
                        Text("不关联").tag(nil as String?)
                        ForEach(store.snapshot?.people ?? []) { person in
                            Text(person.name).tag(person.id as String?)
                        }
                    }
                    Toggle("农历", isOn: $isLunar)
                    Toggle("每年重复", isOn: $repeatYearly)
                } header: {
                    Text("纪念日")
                }

                Section {
                    HStack(spacing: 7) {
                        ForEach([0, 1, 3, 7], id: \.self) { day in
                            Button {
                                if remindDays.contains(day) {
                                    remindDays.remove(day)
                                } else {
                                    remindDays.insert(day)
                                }
                            } label: {
                                Text(day == 0 ? "当天" : "\(day) 天前")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(remindDays.contains(day) ? Color.white : Color.secondary)
                                    .background(
                                        remindDays.contains(day) ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("提前提醒")
                } footer: {
                    Text("按应用设置里的全局时刻投递本地通知。")
                }

                if let error {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("编辑纪念日")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        let ok = await store.updateAnniversary(
            original,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            personID: personID,
            isLunar: isLunar,
            repeatYearly: repeatYearly,
            remindDays: remindDays.sorted()
        )
        isSaving = false
        if ok {
            dismiss()
        } else {
            error = store.error ?? "保存失败"
        }
    }
}

private struct QiansiEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: QiansiModel

    @State private var title = ""
    @State private var date = Date()
    @State private var location = ""
    @State private var selected: Set<String> = []
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题（如：和老王喝茶）", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("地点（可选）", text: $location)
                } header: {
                    Text("约会")
                }

                Section {
                    let people = store.snapshot?.people ?? []
                    if people.isEmpty {
                        Text("还没有联系人可选。").foregroundStyle(.secondary)
                    } else {
                        ForEach(people) { person in
                            Button {
                                if selected.contains(person.id) {
                                    selected.remove(person.id)
                                } else {
                                    selected.insert(person.id)
                                }
                            } label: {
                                HStack {
                                    Text(person.name)
                                    Spacer()
                                    if selected.contains(person.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("参与人")
                } footer: {
                    Text("约会会在设置的全局时刻提前提醒。")
                }

                if let error {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新建约会")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "保存中…" : "保存") {
                        Task { await save() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        error = nil
        let ok = await store.createEvent(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            participantIDs: Array(selected),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        isSaving = false
        if ok {
            dismiss()
        } else {
            error = store.error ?? "保存失败"
        }
    }
}
