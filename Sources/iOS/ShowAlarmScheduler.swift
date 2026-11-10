#if os(iOS)
// AlarmKit 是 iOS 26 才有的新框架，类型还没标 Sendable；本项目开了
// `SWIFT_STRICT_CONCURRENCY: complete`，把它的类型送过 `await` 会被判成数据竞争。
// 框架只有 `shared` 一个入口、且我们把它收进下面的隔离盒里串行使用，
// 用 `@preconcurrency` 把这一层的诊断降下来是安全的。
@preconcurrency import AlarmKit
import Foundation
import Observation
import SwiftUI
import ZhongmiaoCore

/// 闹钟的自定义载荷。
///
/// 目前只用来在系统界面上区分是哪一场（也便于以后做自定义倒计时界面）；
/// 系统返回的 `Alarm` 不带 metadata，所以别指望靠它反查演出。
struct ShowAlarmMetadata: AlarmMetadata {
    var showID: String
    var name: String
}

/// 本地留痕：哪场演出开了闹钟、用的哪个 UUID、什么时候响。
///
/// 为什么必须自己留一份：`Alarm.id` 是我们从演出 id 单向散列出来的，
/// 拿它反推不回演出；而系统只肯告诉我们 `Alarm.id` 的列表。
struct ShowAlarmRecord: Codable, Sendable, Identifiable, Equatable {
    var showID: String
    var uuid: UUID
    var name: String
    var startsAt: Date
    var fireDate: Date
    /// 这一场自己的提前量（分钟）。逐场存而不是读全局设置：
    /// 午场想提前一小时出门、夜场只想提前半小时，两者不该互相覆盖。
    var leadMinutes: Int
    var createdAt: Date

    var id: String { showID }

    private enum CodingKeys: String, CodingKey {
        case showID, uuid, name, startsAt, fireDate, leadMinutes, createdAt
    }

    init(
        showID: String,
        uuid: UUID,
        name: String,
        startsAt: Date,
        fireDate: Date,
        leadMinutes: Int,
        createdAt: Date
    ) {
        self.showID = showID
        self.uuid = uuid
        self.name = name
        self.startsAt = startsAt
        self.fireDate = fireDate
        self.leadMinutes = leadMinutes
        self.createdAt = createdAt
    }

    /// 逐字段解码：早期版本没有 `leadMinutes`，读回来时按当时的响铃时刻反推，
    /// 不要因为多一个字段就把整份留痕判成损坏。
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showID = try container.decode(String.self, forKey: .showID)
        uuid = try container.decode(UUID.self, forKey: .uuid)
        name = try container.decode(String.self, forKey: .name)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        fireDate = try container.decode(Date.self, forKey: .fireDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let stored = try container.decodeIfPresent(Int.self, forKey: .leadMinutes)
        let derived = Int(startsAt.timeIntervalSince(fireDate) / 60)
        leadMinutes = ShowAlarm.clampedLead(stored ?? derived)
    }

    /// 按当前提前量重算响铃时刻（提前量是档位化的，直接乘会有误差）。
    var refreshedFireDate: Date {
        ShowAlarm.fireDate(startsAt: startsAt, leadMinutes: leadMinutes)
    }
}

/// 闹钟留痕的落盘。
///
/// 与 `ShowStore` 同一目录、同一套"读不出来就当空"的策略——
/// 留痕只服务于界面显示与清理，丢了大不了看不见开关，不该让 App 起不来。
actor ShowAlarmStore {

    private(set) var records: [ShowAlarmRecord]
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.records = (try? JSONDecoder().decode([ShowAlarmRecord].self, from: Data(contentsOf: fileURL))) ?? []
    }

    static func standard() -> ShowAlarmStore {
        let manager = FileManager.default
        let base = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let directory = base.appendingPathComponent("Zhongmiao", isDirectory: true)
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return ShowAlarmStore(fileURL: directory.appendingPathComponent("show-alarms.json"))
    }

    func add(_ record: ShowAlarmRecord) {
        records.removeAll { $0.showID == record.showID }
        records.append(record)
        persist()
    }

    func remove(showID: String) {
        records.removeAll { $0.showID == showID }
        persist()
    }

    func remove(showIDs: [String]) {
        let target = Set(showIDs)
        guard !target.isEmpty else { return }
        records.removeAll { target.contains($0.showID) }
        persist()
    }

    func record(showID: String) -> ShowAlarmRecord? {
        records.first { $0.showID == showID }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// 开演闹钟的排程与撤销。
///
/// 为什么值得单独开一条通道：免费个人账号拿不到 Time Sensitive 通知，
/// 本地通知在专注模式下会被静默降级——而"这场演出要迟到了"恰好是最不该被吞的一类。
/// AlarmKit 的闹钟由系统持有，覆盖静音与专注模式，且**不需要任何付费能力**
/// （只要一个使用描述键和用户授权）。
///
/// 因此这里的定位是**用户逐场显式开启的加强通道**，默认一个都不开：
/// 会不会响、响几次，一律由用户在演出详情里决定，App 不替他做主。
@MainActor
@Observable
final class ShowAlarmScheduler {

    enum Authorization: Equatable {
        case notDetermined
        case denied
        case authorized

        var isAuthorized: Bool { self == .authorized }

        var description: String {
            switch self {
            case .notDetermined: "未询问"
            case .denied: "已拒绝"
            case .authorized: "已授权"
            }
        }
    }

    /// 已开启闹钟的演出 id。界面据此显示开关状态。
    private(set) var alarmShowIDs: Set<String> = []
    private(set) var authorization: Authorization = .notDetermined
    /// 最近一次失败的原因，界面直接展示。
    private(set) var lastError: String?
    /// 轻量对齐的节流点：详情重现、回到前台都可能触发，短时间内只查一次系统。
    private var lastReconcileAt: Date?

    private let store = ShowAlarmStore.standard()
    private let manager = AlarmManager.shared

    // MARK: - 状态

    func isSet(showID: String) -> Bool { alarmShowIDs.contains(showID) }

    var count: Int { alarmShowIDs.count }

    var canAddMore: Bool { alarmShowIDs.count < ShowAlarm.maxConcurrent }

    /// 与系统对齐：读取系统里真实存在的闹钟，清掉本地留痕中的孤儿。
    ///
    /// 典型场景是用户在系统闹钟里删了一个——留痕还留着，开关就会显示错。
    /// 另一个场景是 7 天签名过期期间闹钟照旧响了、过期了，重新打开 App 时收尾。
    func reconcile(now: Date = .now) async {
        // 详情每次出现、以及从系统“时钟”返回前台都会调用；2 秒内只查一次，
        // 既能让开关及时对齐，又不会在页面切换时反复读系统列表。
        if let lastReconcileAt, now.timeIntervalSince(lastReconcileAt) < 2 { return }
        lastReconcileAt = now

        let systemIDs: Set<UUID>
        do {
            systemIDs = Set(try manager.alarms.map(\.id))
        } catch {
            // 读不到系统列表时不要清空留痕：宁可显示成已开，也不能把用户真开着的闹钟的记录抹掉。
            lastError = "读取系统闹钟失败：\(error.localizedDescription)"
            return
        }

        let mine = await store.records
        let stale = mine.filter { record in
            !systemIDs.contains(record.uuid) || record.fireDate < now
        }
        let orphanIDs = stale.map(\.showID)
        if !orphanIDs.isEmpty {
            await store.remove(showIDs: orphanIDs)
        }
        let kept = mine.filter { !Set(orphanIDs).contains($0.showID) }
        alarmShowIDs = Set(kept.map(\.showID))
        authorization = map(manager.authorizationState)
    }

    // MARK: - 写入

    /// 开启一场演出的闹钟。返回是否成功。
    @discardableResult
    func enable(_ plan: ShowAlarmPlan) async -> Bool {
        lastError = nil
        guard await ensureAuthorized() else {
            // 说不清是设备不支持（模拟器、旧系统）还是用户在设置里关掉了——
            // 两种情况下系统都只给 denied，所以文案要同时覆盖，别把用户支到没有开关的地方。
            lastError = "没能开启系统闹钟：这台设备不支持，或众妙的闹钟权限是关闭的（到「设置 → 众妙」里检查）。"
            return false
        }
        guard canAddMore else {
            lastError = "同时最多开 \(ShowAlarm.maxConcurrent) 个闹钟，先取消一个再开。"
            return false
        }
        guard ShowAlarm.isSchedulable(fireDate: plan.fireDate) else {
            lastError = "这场已经来不及排闹钟了。"
            return false
        }

        let id = ShowAlarm.identifier(forShowID: plan.showID)
        do {
            // 先撤后建：同一 id 重复排的行为官方没写死，撤一次最稳。
            try? manager.cancel(id: id)
            _ = try await manager.schedule(id: id, configuration: configuration(for: plan))
        } catch {
            if case AlarmManager.AlarmError.maximumLimitReached = error {
                lastError = "系统闹钟已达上限，先到系统「时钟」里清掉几个。"
            } else {
                lastError = "排闹钟失败：\(error.localizedDescription)"
            }
            return false
        }

        await store.add(
            ShowAlarmRecord(
                showID: plan.showID,
                uuid: id,
                name: plan.name,
                startsAt: plan.startsAt,
                fireDate: plan.fireDate,
                leadMinutes: plan.leadMinutes,
                createdAt: .now
            )
        )
        alarmShowIDs.insert(plan.showID)
        return true
    }

    /// 这一场当前用的提前量；没开过闹钟时回落到设置里的默认档位。
    func leadMinutes(forShowID showID: String, fallback: Int = ShowAlarm.defaultLeadMinutes) async -> Int {
        await store.record(showID: showID)?.leadMinutes ?? ShowAlarm.clampedLead(fallback)
    }

    /// 关掉一场演出的闹钟。演出取消、看过了、不想响了都走这里。
    func disable(showID: String) async {
        lastError = nil
        let id = ShowAlarm.identifier(forShowID: showID)
        do {
            try manager.cancel(id: id)
        } catch {
            // 系统里本来就没有（用户已删）不算失败，只清留痕。
        }
        await store.remove(showID: showID)
        alarmShowIDs.remove(showID)
    }

    /// 改提前量后重排：撤掉旧的、按新时刻重建。
    func reschedule(_ plan: ShowAlarmPlan) async -> Bool {
        let id = ShowAlarm.identifier(forShowID: plan.showID)
        try? manager.cancel(id: id)
        guard ShowAlarm.isSchedulable(fireDate: plan.fireDate) else {
            await store.remove(showID: plan.showID)
            alarmShowIDs.remove(plan.showID)
            lastError = "这场已经来不及排闹钟了。"
            return false
        }
        do {
            _ = try await manager.schedule(id: id, configuration: configuration(for: plan))
        } catch {
            lastError = "重排闹钟失败：\(error.localizedDescription)"
            return false
        }
        await store.add(
            ShowAlarmRecord(
                showID: plan.showID,
                uuid: id,
                name: plan.name,
                startsAt: plan.startsAt,
                fireDate: plan.fireDate,
                leadMinutes: plan.leadMinutes,
                createdAt: .now
            )
        )
        alarmShowIDs.insert(plan.showID)
        return true
    }

    /// 清掉所有已过期的闹钟（含总开关关闭时的全撤）。
    func cancelAll() async {
        let mine = await store.records
        for record in mine {
            try? manager.cancel(id: record.uuid)
        }
        await store.remove(showIDs: mine.map(\.showID))
        alarmShowIDs = []
    }

    // MARK: - 内部

    private func configuration(for plan: ShowAlarmPlan) -> AlarmManager.AlarmConfiguration<ShowAlarmMetadata> {
        let lead = Int(plan.startsAt.timeIntervalSince(plan.fireDate) / 60)
        let title: LocalizedStringResource = lead >= 60
            ? "《\(plan.name)》还有 \(lead / 60) 小时开演"
            : "《\(plan.name)》还有 \(max(lead, 1)) 分钟开演"
        let presentation = AlarmPresentation(alert: .init(title: title))
        let attributes = AlarmAttributes<ShowAlarmMetadata>(
            presentation: presentation,
            metadata: ShowAlarmMetadata(showID: plan.showID, name: plan.name),
            tintColor: .purple
        )
        return AlarmManager.AlarmConfiguration(
            schedule: .fixed(plan.fireDate),
            attributes: attributes
        )
    }

    private func ensureAuthorized() async -> Bool {
        let current = map(manager.authorizationState)
        authorization = current
        if current.isAuthorized { return true }
        guard current == .notDetermined else { return false }
        do {
            let state = try await manager.requestAuthorization()
            authorization = map(state)
        } catch {
            authorization = .denied
        }
        return authorization.isAuthorized
    }

    private func map(_ state: AlarmManager.AuthorizationState) -> Authorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}
#endif
