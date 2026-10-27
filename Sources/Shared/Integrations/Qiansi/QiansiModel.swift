import Foundation
import Observation
import ZhongmiaoCore

@MainActor
@Observable
final class QiansiModel {

    enum Filter: String, CaseIterable, Identifiable {
        case reminders
        case birthdays
        case dates
        case contacts

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reminders: "提醒"
            case .birthdays: "生日"
            case .dates: "约会"
            case .contacts: "联系人"
            }
        }
    }

    let service: ServiceDefinition
    let baseURL: URL
    let center: IntegrationCenter

    private(set) var snapshot: QiansiSnapshot?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var searchResults: [QiansiPerson]?
    var filter: Filter = .reminders
    var searchText = ""
    var expandedID: String?

    init(service: ServiceDefinition, baseURL: URL, center: IntegrationCenter) {
        self.service = service
        self.baseURL = baseURL
        self.center = center
    }

    private var client: QiansiClient {
        QiansiClient(baseURL: baseURL, token: center.credential(for: "qiansi")?.bearer)
    }

    // MARK: - 读取

    func loadCache() async {
        guard snapshot == nil else { return }
        if let cached = await center.cache.load(QiansiSnapshot.self, serviceID: "qiansi") {
            snapshot = cached.payload
            lastUpdated = cached.fetchedAt
            await rescheduleReminders()
        }
    }

    func refreshIfNeeded() async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < 300 { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        let to = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        do {
            async let people = client.people()
            async let anniversaries = client.anniversaries()
            async let reminders = client.upcomingReminders()
            async let events = client.events(from: .now, to: to)
            let stats = try? await client.dashboard()

            let value = QiansiSnapshot(
                people: try await people,
                anniversaries: try await anniversaries,
                reminders: try await reminders,
                events: try await events,
                stats: stats
            )
            snapshot = value
            lastUpdated = .now
            center.markValid(serviceID: "qiansi")
            await center.cache.save(value, serviceID: "qiansi")
            await rescheduleReminders()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
        }
        isLoading = false
    }

    func searchPeople() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            return
        }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            searchResults = try await client.people(query: query)
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
        }
    }

    // MARK: - 写操作

    func complete(reminderID: String) async {
        do {
            try await client.completeReminder(id: reminderID)
            if var value = snapshot {
                value.reminders.removeAll { $0.id == reminderID }
                snapshot = value
                await center.cache.save(value, serviceID: "qiansi")
            }
            await rescheduleReminders()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
        }
    }

    func createAnniversary(
        title: String,
        date: Date,
        personID: String?,
        isLunar: Bool,
        repeatYearly: Bool,
        remindDays: [Int]
    ) async -> Bool {
        do {
            _ = try await client.createAnniversary(
                title: title,
                date: QiansiLocalDate.dayString(date),
                personID: personID,
                isLunar: isLunar,
                repeatYearly: repeatYearly,
                remindDays: remindDays
            )
            await refresh()
            return true
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
            return false
        }
    }

    /// 改纪念日。服务端是全量覆盖，未改动的字段按原值一起带回去。
    func updateAnniversary(
        _ original: QiansiAnniversary,
        title: String,
        date: Date,
        personID: String?,
        isLunar: Bool,
        repeatYearly: Bool,
        remindDays: [Int]
    ) async -> Bool {
        do {
            _ = try await client.updateAnniversary(
                id: original.id,
                title: title,
                date: QiansiLocalDate.dayString(date),
                personID: personID,
                isLunar: isLunar,
                repeatYearly: repeatYearly,
                remindDays: remindDays
            )
            await refresh()
            return true
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
            return false
        }
    }

    /// 归档纪念日。
    func archiveAnniversary(id: String) async -> Bool {
        do {
            try await client.archiveAnniversary(id: id)
            await refresh()
            return true
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
            return false
        }
    }

    /// 归档约会。
    func archiveEvent(id: String) async -> Bool {
        do {
            try await client.archiveEvent(id: id)
            await refresh()
            return true
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
            return false
        }
    }

    /// 按 id 找原始纪念日（编辑时要按原始记录回写）。
    func anniversary(id: String) -> QiansiAnniversary? {
        snapshot?.anniversaries.first { $0.id == id }
    }

    func createEvent(
        title: String,
        date: Date,
        participantIDs: [String],
        location: String
    ) async -> Bool {
        do {
            _ = try await client.createEvent(
                title: title,
                date: QiansiLocalDate.dayString(date),
                participantIDs: participantIDs,
                location: location
            )
            await refresh()
            return true
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qiansi")
            return false
        }
    }

    // MARK: - 派生数据

    var people: [QiansiPerson] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let searchResults {
            return searchResults
        }
        return snapshot?.people ?? []
    }

    var agendaItems: [QiansiAgendaItem] {
        guard let snapshot else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
        var items: [QiansiAgendaItem] = []

        for anniversary in snapshot.anniversaries {
            let raw = anniversary.nextDate ?? anniversary.date
            guard let date = QiansiLocalDate.parse(raw) else { continue }
            let days = anniversary.daysUntil ?? QiansiLocalDate.daysUntil(date)
            items.append(
                QiansiAgendaItem(
                    id: "anniversary:\(anniversary.id)",
                    date: date,
                    title: anniversary.title,
                    subtitle: anniversary.personName ?? (anniversary.isLunar == true ? "农历" : "纪念日"),
                    kind: .anniversary,
                    reminderID: nil,
                    personID: anniversary.personId,
                    daysUntil: days
                )
            )
        }

        for event in snapshot.events {
            guard let date = QiansiLocalDate.parse(event.eventDate),
                  date >= today else { continue }
            let names = event.participants?.map(\.name).joined(separator: "、") ?? ""
            let subtitle = [event.location, names]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            items.append(
                QiansiAgendaItem(
                    id: "event:\(event.id)",
                    date: date,
                    title: event.title,
                    subtitle: subtitle.isEmpty ? "约会" : subtitle,
                    kind: .event,
                    reminderID: nil,
                    personID: nil,
                    daysUntil: QiansiLocalDate.daysUntil(date)
                )
            )
        }

        for reminder in snapshot.reminders where reminder.status != "done" {
            // 生日/纪念日的派生提醒由本地按 remind_days 重排，避免与上面的纪念日重复。
            if reminder.refType == "anniversary" || reminder.refType == "birthday" {
                continue
            }
            guard let date = QiansiLocalDate.parse(reminder.dueAt) else { continue }
            items.append(
                QiansiAgendaItem(
                    id: "reminder:\(reminder.id)",
                    date: date,
                    title: reminder.title,
                    subtitle: reminderSubtitle(reminder),
                    kind: .reminder,
                    reminderID: reminder.id,
                    personID: reminder.personId,
                    daysUntil: QiansiLocalDate.daysUntil(date)
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.date == rhs.date { return lhs.title < rhs.title }
            return lhs.date < rhs.date
        }
    }

    var filteredAgenda: [QiansiAgendaItem] {
        switch filter {
        case .reminders: agendaItems
        case .birthdays: agendaItems.filter { $0.kind == .anniversary }
        case .dates: agendaItems.filter { $0.kind == .event }
        case .contacts: []
        }
    }

    var agendaGroups: [(day: Date, items: [QiansiAgendaItem])] {
        let grouped = Dictionary(grouping: filteredAgenda) {
            Calendar.current.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var dueTodayCount: Int {
        agendaItems.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var next7Count: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let limit = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        return agendaItems.filter { $0.date >= start && $0.date <= limit }.count
    }

    private func reminderSubtitle(_ reminder: QiansiReminder) -> String {
        if let name = reminder.personName, !name.isEmpty {
            return name
        }
        switch reminder.refType {
        case "custom": return "提醒"
        case "promise": return "承诺"
        case "contact": return "联系节奏"
        case "memo": return "备忘"
        default: return "提醒"
        }
    }

    var peopleCount: Int {
        if let value = snapshot?.stats?.totalPeople { return value }
        return snapshot?.people.count ?? 0
    }

    // MARK: - 提醒

    func rescheduleReminders() async {
        guard let snapshot else { return }
        let preference = center.preference(for: "qiansi")

        let anniversaries: [AnniversaryReminderInput] = snapshot.anniversaries.compactMap { anniversary in
            let raw = anniversary.nextDate ?? anniversary.date
            guard let date = QiansiLocalDate.parse(raw) else { return nil }
            return AnniversaryReminderInput(
                id: anniversary.id,
                title: anniversary.title,
                personName: anniversary.personName,
                nextDate: date,
                daysUntil: anniversary.daysUntil ?? QiansiLocalDate.daysUntil(date),
                remindDays: anniversary.remindDayOffsets
            )
        }

        let events: [EventReminderInput] = snapshot.events.compactMap { event in
            guard let date = QiansiLocalDate.parse(event.eventDate) else { return nil }
            return EventReminderInput(
                id: event.id,
                title: event.title,
                date: date,
                people: event.participants?.map(\.name) ?? []
            )
        }

        let customReminders: [CustomReminderInput] = snapshot.reminders.compactMap { reminder in
            if reminder.refType == "anniversary" || reminder.refType == "birthday" {
                return nil
            }
            guard reminder.status != "done",
                  let dueAt = QiansiLocalDate.parse(reminder.dueAt) else { return nil }
            return CustomReminderInput(
                id: reminder.id,
                title: reminder.title,
                dueAt: dueAt,
                personName: reminder.personName
            )
        }

        let plans = QiansiReminderPlanner.plan(
            anniversaries: anniversaries,
            events: events,
            customReminders: customReminders,
            hour: preference.reminderHour,
            minute: preference.reminderMinute,
            eventLeadDays: preference.eventLeadDays
        )
        await center.syncReminders(serviceID: "qiansi", plans: plans)
    }
}
