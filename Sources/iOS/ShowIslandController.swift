import ActivityKit
import Foundation
import ZhongmiaoCore

/// 灵动岛的开启、更新与收起。
///
/// 设计前提：**没有 APNs**。所以 `pushType` 一律传 `nil`——
/// 这表示「本活动不通过推送更新」，ActivityKit 也就不会去要推送权限与证书。
/// 免费个人开发者账号能用灵动岛，靠的就是这一点。
///
/// 本控制器被三个触发点共用：打开 App、快捷指令自动化、通知上的「盯场」按钮。
/// 三者都调用同一个 `align`，所以它是幂等的：重复调用只会更新状态，不会开出第二个岛。
@MainActor
final class ShowIslandController {

    static let shared = ShowIslandController()

    private init() {}

    enum Outcome: Sendable {
        case started(String)
        case updated(String)
        case ended(String)
        case unchanged(String)
        /// 此刻没有该上岛的演出。这是常态——一天里绝大多数时刻都是它。
        case noShow
        /// 用户在系统设置里关掉了本 App 的实时活动。
        case disabled
        case failed(String)

        var isSuccess: Bool {
            switch self {
            case .started, .updated, .ended, .unchanged, .noShow: return true
            case .disabled, .failed: return false
            }
        }

        var logText: String {
            switch self {
            case .started(let name): return "已开《\(name)》"
            case .updated(let name): return "已更新《\(name)》"
            case .ended(let name): return "已收起《\(name)》"
            case .unchanged(let name): return "《\(name)》已在岛上"
            case .noShow: return "此刻没有该上岛的演出"
            case .disabled: return "系统已关闭本 App 的实时活动"
            case .failed(let reason): return "开启失败：\(reason)"
            }
        }
    }

    /// 让岛的状态与当前时刻对齐。
    ///
    /// - Parameters:
    ///   - shows: 缓存中尚未散场的演出。
    ///   - lead: 允许提前多久开岛。
    func align(shows: [Show], lead: TimeInterval, now: Date = .now) async -> Outcome {
        // iOS 26 起这是个实例属性而非类型属性：用户可以在系统设置里随时关掉实时活动，
        // 每次开岛前都要问一次，问不到就只能放弃（此时岛根本不会出现）。
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }

        // 每次都向系统问一遍，而不是信任内存里的引用：
        // 快捷指令拉起的是新进程，内存里什么都没有，但岛可能正挂在屏幕上。
        let running = await Activity<ShowActivityAttributes>.activities
            .first { $0.activityState == .active }

        if let running {
            let handle = ActivityHandle(value: running)
            let runningName = handle.value.attributes.name

            // 岛已经在跑：要么更新阶段，要么到点收起。绝不开第二个。
            guard let show = shows.first(where: { $0.id == handle.value.attributes.showID }) else {
                await handle.value.end(nil, dismissalPolicy: .immediate)
                return .ended(runningName)
            }

            if now >= show.islandDismissAt {
                await handle.value.end(nil, dismissalPolicy: .immediate)
                return .ended(show.name)
            }

            let phase = show.phase(now: now)
            if handle.value.content.state.phase != phase {
                await handle.value.update(ShowIslandController.content(for: show, now: now))
                return .updated(show.name)
            }
            return .unchanged(show.name)
        }

        let library = ShowLibrary(items: shows)
        guard let show = library.showForIsland(now: now, lead: lead) else { return .noShow }

        do {
            _ = try Activity.request(
                attributes: ShowIslandController.attributes(for: show),
                content: ShowIslandController.content(for: show, now: now),
                pushType: nil
            )
            return .started(show.name)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// 立刻收起全部演出岛（总开关关闭时）。
    func endAll() async {
        for activity in await Activity<ShowActivityAttributes>.activities {
            await ActivityHandle(value: activity).value.end(nil, dismissalPolicy: .immediate)
        }
    }

    // MARK: - 载荷

    /// `Activity` 不是 `Sendable`，而 `end`/`update` 都是 async 方法，
    /// Swift 6 严格并发会拒绝把它送过 await 边界。装箱是 EventKit 同类问题的标准解法：
    /// 这里没有任何跨线程共享，全部使用都发生在同一个 `@MainActor` 方法内。
    private struct ActivityHandle: @unchecked Sendable {
        let value: Activity<ShowActivityAttributes>
    }

    private static func attributes(for show: Show) -> ShowActivityAttributes {
        ShowActivityAttributes(
            showID: show.id,
            name: show.name,
            venue: show.venue,
            seat: show.seat,
            startsAt: show.startsAt,
            url: show.url?.absoluteString
        )
    }

    private static func content(
        for show: Show,
        now: Date
    ) -> ActivityContent<ShowActivityAttributes.ContentState> {
        let state = ShowActivityAttributes.ContentState(
            phase: show.phase(now: now),
            endsAt: show.endsAt
        )
        return ActivityContent(state: state, staleDate: nil)
    }
}
