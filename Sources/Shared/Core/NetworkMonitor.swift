import Foundation
import Network
import Observation

/// 网络状态与"重连"事件源。
///
/// 断线重连是补发链路的关键触发点：一旦从离线切回在线，
/// `onReconnect` 会驱动一次全量同步，把离线期间积压的事件补齐。
@MainActor
@Observable
final class NetworkMonitor {

    private(set) var isOnline = true
    private(set) var isExpensive = false
    private(set) var isConstrained = false
    private(set) var interfaceName: String = ""

    /// 连续状态变化次数，便于 UI 观察真实抖动而非单次回调。
    private(set) var transitionCount = 0

    /// 重连回调（离线 → 在线）。
    var onReconnect: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "im.yufei.zhongmiao.network")
    private var hasStarted = false

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            let name = path.usesInterfaceType(.wifi)
                ? "Wi‑Fi"
                : (path.usesInterfaceType(.cellular) ? "蜂窝网络" : "有线/其他")

            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                let changed = wasOnline != online
                self.isOnline = online
                self.isExpensive = expensive
                self.isConstrained = constrained
                self.interfaceName = name
                if changed {
                    self.transitionCount += 1
                    if online {
                        self.onReconnect?()
                    }
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    var summary: String {
        guard isOnline else { return "离线" }
        var parts = [interfaceName.isEmpty ? "在线" : interfaceName]
        if isExpensive { parts.append("计费网络") }
        if isConstrained { parts.append("低数据模式") }
        return parts.joined(separator: " · ")
    }
}
