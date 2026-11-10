#if os(iOS)
import SwiftUI
import ZhongmiaoCore

/// 演出详情里的「开演闹钟」。
///
/// 设计上刻意做成一个**纯手动**的开关：
/// - 默认关闭，哪一场要响由用户自己按；
/// - 开启后由系统持有，App 被杀、描述文件过期都照响，也会穿透静音与专注模式；
/// - 因此文案必须说清楚"会响"，不能让用户以为这只是另一条通知。
struct ShowAlarmSection: View {

    let showID: String
    let name: String
    let venue: String?
    let seat: String?
    let startsAt: Date

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var isWorking = false
    @State private var error: String?
    /// 这一场的提前量。逐场存，改一场不影响别的场次。
    @State private var leadMinutes: Int = ShowAlarm.defaultLeadMinutes

    var body: some View {
        Section {
            Toggle(isOn: toggle) {
                Label("开演闹钟", systemImage: "alarm")
            }
            .disabled(isWorking || !canSchedule)

            if isOn {
                LabeledContent("响铃时刻") {
                    Text(fireDate.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute()))
                        .foregroundStyle(.secondary)
                }
                Picker("提前", selection: lead) {
                    ForEach(ShowAlarm.leadOptions, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                .disabled(isWorking)
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let message = model.showAlarms.lastError, isOn {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !canSchedule {
                Text("这场已经开演，来不及排闹钟了。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(footerText)
        }
        .task {
            // 每次进入详情都与系统对齐；调度器内部有 2 秒节流，不会反复读系统列表。
            await model.showAlarms.reconcile()
            leadMinutes = await model.showAlarms.leadMinutes(
                forShowID: showID,
                fallback: model.settings.showsAlarmLead
            )
        }
        .onChange(of: scenePhase) { _, phase in
            // 用户去系统「时钟」删掉闹钟后回到 App，详情页通常不会重建，
            // 这里补一次对齐，让开关跟着系统状态回关。
            guard phase == .active else { return }
            Task { await model.showAlarms.reconcile() }
        }
    }

    // MARK: - 状态

    private var alarms: ShowAlarmScheduler { model.showAlarms }

    private var isOn: Bool { alarms.isSet(showID: showID) }

    private var fireDate: Date {
        ShowAlarm.fireDate(startsAt: startsAt, leadMinutes: leadMinutes)
    }

    private var canSchedule: Bool {
        ShowAlarm.isSchedulable(fireDate: fireDate)
    }

    private var toggle: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                Task { await apply(newValue) }
            }
        )
    }

    private var lead: Binding<Int> {
        Binding(
            get: { leadMinutes },
            set: { newValue in
                guard newValue != leadMinutes else { return }
                leadMinutes = newValue
                guard isOn else { return }
                Task { await reschedule() }
            }
        )
    }

    private var footerText: String {
        if isOn {
            return "闹钟由系统在 \(leadMinutes) 分钟前响起，会覆盖静音与专注模式——这是它和普通提醒唯一的区别。开演后自动失效。"
        }
        if !alarms.canAddMore {
            return "同时最多开 \(ShowAlarm.maxConcurrent) 个闹钟，先取消一个再开。默认不响，只有你打开才响。"
        }
        return "默认不响。打开后由系统在开演前 \(leadMinutes) 分钟响一次，覆盖静音与专注模式；普通提醒照旧不受影响。"
    }

    // MARK: - 动作

    private func apply(_ newValue: Bool) async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        if newValue {
            guard let plan = plan() else {
                error = "这场已经来不及排闹钟了。"
                return
            }
            let ok = await alarms.enable(plan)
            if !ok { error = alarms.lastError ?? "没能开启闹钟。" }
        } else {
            await alarms.disable(showID: showID)
        }
    }

    private func reschedule() async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        guard let plan = plan() else {
            error = "这场已经来不及排闹钟了。"
            return
        }
        let ok = await alarms.reschedule(plan)
        if !ok { error = alarms.lastError ?? "没能更新闹钟。" }
    }

    private func plan() -> ShowAlarmPlan? {
        ShowAlarm.plan(
            for: showID,
            name: name,
            venue: venue,
            seat: seat,
            startsAt: startsAt,
            leadMinutes: leadMinutes
        )
    }
}
#endif
