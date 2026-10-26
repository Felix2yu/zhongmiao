#if os(iOS)
import BackgroundTasks
import Foundation

/// 后台刷新：把"拉取 → 去重 → 投递"搬到系统给的后台时间片里。
///
/// 注意这是**尽力而为**的机制：系统会根据使用频率、电量、低数据模式调整调度，
/// 所以它只作为 APNs 之外的补充，真正的保底是"下次前台/重连时全量补发"。
enum BackgroundSync {

    static let refreshIdentifier = "im.yufei.zhongmiao.refresh"

    /// BGTask 不是 Sendable，用一个受控包装跨隔离域传递。
    private final class TaskHandle: @unchecked Sendable {
        private let task: BGAppRefreshTask

        init(_ task: BGAppRefreshTask) {
            self.task = task
        }

        func complete(success: Bool) {
            task.setTaskCompleted(success: success)
        }
    }

    /// 必须在 application(_:didFinishLaunchingWithOptions:) 返回前调用。
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    static func schedule(after seconds: TimeInterval = 20 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: max(60, seconds))
        BGTaskScheduler.shared.submitTaskRequest(request) { _ in
            // 模拟器与未授权的环境会失败，属于预期行为，不打扰用户。
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // 先排下一次，避免被系统降频后彻底不再调度。
        schedule()

        let handle = TaskHandle(task)
        let work = Task { @MainActor in
            await AppModel.shared.performBackgroundSync()
            // 顺带刷一次演出：后台时间片不保证落在开演前，能刷到一次就多一次排程机会。
            await AppModel.shared.refreshShows()
        }

        let cancel: @Sendable () -> Void = { [work] in
            work.cancel()
        }
        task.expirationHandler = cancel

        Task { @MainActor in
            await work.value
            handle.complete(success: !work.isCancelled)
        }
    }
}
#endif
