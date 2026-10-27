import Foundation
import Observation
import ZhongmiaoCore

@MainActor
@Observable
final class ShenshiModel {

    let service: ServiceDefinition
    let baseURL: URL
    let center: IntegrationCenter

    private(set) var snapshot: ShenshiSnapshot?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var busyTaskIDs: Set<Int64> = []
    private(set) var busyHabitIDs: Set<Int64> = []
    var expandedTaskID: Int64?

    init(service: ServiceDefinition, baseURL: URL, center: IntegrationCenter) {
        self.service = service
        self.baseURL = baseURL
        self.center = center
    }

    private var client: ShenshiClient {
        ShenshiClient(baseURL: baseURL, token: center.credential(for: "shenshi")?.bearer ?? "")
    }

    func loadCache() async {
        guard snapshot == nil else { return }
        if let cached = await center.cache.load(ShenshiSnapshot.self, serviceID: "shenshi") {
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
        do {
            async let today = client.tasks(smart: "today")
            async let overdue = client.tasks(smart: "overdue")
            async let habits = client.habits()
            async let reminders = client.reminders()
            let stats = try? await client.stats()
            let board = try await habits

            let value = ShenshiSnapshot(
                today: try await today,
                overdue: try await overdue,
                habits: board.habits,
                habitStats: board.stats ?? [],
                reminders: try await reminders,
                stats: stats
            )
            snapshot = value
            lastUpdated = .now
            center.markValid(serviceID: "shenshi")
            await center.cache.save(value, serviceID: "shenshi")
            await rescheduleReminders()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "shenshi")
        }
        isLoading = false
    }

    func complete(_ task: ShenshiTask, completed: Bool) async {
        guard !busyTaskIDs.contains(task.id) else { return }
        busyTaskIDs.insert(task.id)
        do {
            try await client.setDone(taskID: task.id, completed: completed)
            await refresh()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "shenshi")
        }
        busyTaskIDs.remove(task.id)
    }

    func check(_ habit: ShenshiHabit) async {
        guard !busyHabitIDs.contains(habit.id) else { return }
        busyHabitIDs.insert(habit.id)
        do {
            try await client.checkHabit(id: habit.id)
            await refresh()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "shenshi")
        }
        busyHabitIDs.remove(habit.id)
    }

    func habitStat(for habitID: Int64) -> ShenshiHabitStat? {
        snapshot?.habitStats.first { $0.habitId == habitID }
    }

    func rescheduleReminders() async {
        let plans: [PlannedReminder] = (snapshot?.reminders ?? []).compactMap { hit in
            guard let fireDate = ShenshiDate.parse(hit.fireAt), fireDate > .now else { return nil }
            return PlannedReminder(
                id: IntegrationReminderID.make(
                    serviceID: "shenshi",
                    kind: "due",
                    key: String(hit.ackId),
                    date: fireDate
                ),
                serviceID: "shenshi",
                title: hit.task.title,
                body: hit.dueLabel ?? "慎始提醒",
                fireDate: fireDate,
                userInfo: ["taskId": String(hit.task.id)]
            )
        }
        await center.syncReminders(serviceID: "shenshi", plans: plans)
    }
}
