import Foundation
import Observation
import ZhongmiaoCore

@MainActor
@Observable
final class QingyeModel {

    let service: ServiceDefinition
    let baseURL: URL
    let center: IntegrationCenter

    private let client: QingyeClient

    private(set) var snapshot: QingyeSnapshot?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var busyTaskIDs: Set<Int> = []
    private(set) var busyPlantIDs: Set<Int> = []
    var selectedRoomID: Int?
    var expandedTaskID: Int?

    /// 点通知进来时要看的那一天。
    var focusDate: Date?

    /// 那一天的任务。今天/明天/逾期已经在下面的分组里列过，不重复单列。
    var focusTasks: [QingyeTask] {
        guard let focusDate else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let day = calendar.startOfDay(for: focusDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)
        if day <= today || day == tomorrow { return [] }
        return activeTasks.filter { calendar.isDate($0.nextDue, inSameDayAs: day) }
    }

    /// 聚焦那天的分组标题。
    var focusDayLabel: String {
        guard let focusDate else { return "" }
        return focusDate.formatted(.dateTime.month().day().weekday(.abbreviated))
    }
    var expandedPlantID: Int?

    init(service: ServiceDefinition, baseURL: URL, center: IntegrationCenter) {
        self.service = service
        self.baseURL = baseURL
        self.center = center
        self.client = QingyeClient(baseURL: baseURL)
    }

    // MARK: - 读取

    func loadCache() async {
        guard snapshot == nil else { return }
        if let cached = await center.cache.load(QingyeSnapshot.self, serviceID: "qingye") {
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
            async let rooms = client.rooms()
            async let plants = client.plants()
            async let tasks = client.upcomingTasks()
            async let logs = client.careLogs()
            let value = QingyeSnapshot(
                rooms: try await rooms,
                plants: try await plants,
                tasks: try await tasks,
                careLogs: try await logs
            )
            snapshot = value
            lastUpdated = .now
            await center.cache.save(value, serviceID: "qingye")
            await rescheduleReminders()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qingye")
        }
        isLoading = false
    }

    // MARK: - 操作

    func complete(_ task: QingyeTask, note: String) async {
        guard !busyTaskIDs.contains(task.id) else { return }
        busyTaskIDs.insert(task.id)
        do {
            _ = try await client.completeTask(id: task.id, note: note)
            expandedTaskID = nil
            await refresh()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qingye")
        }
        busyTaskIDs.remove(task.id)
    }

    func postpone(_ task: QingyeTask, days: Int, note: String) async {
        guard !busyTaskIDs.contains(task.id) else { return }
        busyTaskIDs.insert(task.id)
        do {
            _ = try await client.postponeTask(id: task.id, days: days, note: note)
            expandedTaskID = nil
            await refresh()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qingye")
        }
        busyTaskIDs.remove(task.id)
    }

    func recordCare(plant: QingyePlant, type: String, title: String) async {
        guard !busyPlantIDs.contains(plant.id) else { return }
        busyPlantIDs.insert(plant.id)
        do {
            _ = try await client.addCareLog(
                plantID: plant.id,
                type: type,
                title: title,
                note: "",
                at: .now
            )
            await refresh()
        } catch {
            self.error = (error as? IntegrationAPIError)?.userMessage ?? error.localizedDescription
            center.reportError(error, for: "qingye")
        }
        busyPlantIDs.remove(plant.id)
    }

    // MARK: - 派生数据

    var rooms: [QingyeRoom] { snapshot?.rooms ?? [] }

    var plants: [QingyePlant] {
        let all = snapshot?.plants ?? []
        guard let selectedRoomID else { return all }
        return all.filter { $0.roomId == selectedRoomID }
    }

    var activeTasks: [QingyeTask] {
        (snapshot?.tasks ?? [])
            .filter(\.active)
            .filter { selectedRoomID == nil || $0.plant?.roomId == selectedRoomID }
            .sorted { $0.nextDue < $1.nextDue }
    }

    var overdueTasks: [QingyeTask] {
        activeTasks.filter { $0.nextDue < Calendar.current.startOfDay(for: .now) }
    }

    var todayTasks: [QingyeTask] {
        activeTasks.filter { Calendar.current.isDateInToday($0.nextDue) }
    }

    var tomorrowTasks: [QingyeTask] {
        activeTasks.filter {
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)) else {
                return false
            }
            return Calendar.current.isDate($0.nextDue, inSameDayAs: tomorrow)
        }
    }

    var laterTasks: [QingyeTask] {
        let calendar = Calendar.current
        guard let dayAfterTomorrow = calendar.date(
            byAdding: .day,
            value: 2,
            to: calendar.startOfDay(for: .now)
        ) else { return [] }
        return activeTasks.filter { $0.nextDue >= dayAfterTomorrow }
    }

    var plantCount: Int { snapshot?.plants.count ?? 0 }

    func logs(for plantID: Int) -> [QingyeCareLog] {
        (snapshot?.careLogs ?? []).filter { $0.plantId == plantID }.prefix(3).map { $0 }
    }

    func tasks(for plantID: Int) -> [QingyeTask] {
        (snapshot?.tasks ?? []).filter { $0.plantId == plantID && $0.active }
    }

    var roomGroups: [(room: QingyeRoom?, plants: [QingyePlant])] {
        let grouped = Dictionary(grouping: plants) { $0.roomId }
        var result: [(QingyeRoom?, [QingyePlant])] = []
        for room in rooms {
            if let items = grouped[room.id], !items.isEmpty {
                result.append((room, items.sorted { $0.name < $1.name }))
            }
        }
        if let orphans = grouped[0], !orphans.isEmpty {
            result.append((nil, orphans.sorted { $0.name < $1.name }))
        }
        return result
    }

    // MARK: - 提醒

    func rescheduleReminders() async {
        let preference = center.preference(for: "qingye")
        let tasks = (snapshot?.tasks ?? []).map { task in
            CareReminderInput(
                id: task.id,
                plantName: task.plant?.name ?? "植物",
                title: task.title,
                nextDue: task.nextDue,
                active: task.active
            )
        }
        let plans = QingyeReminderPlanner.plan(
            tasks: tasks,
            hour: preference.reminderHour,
            minute: preference.reminderMinute
        )
        await center.syncReminders(serviceID: "qingye", plans: plans)
    }
}
