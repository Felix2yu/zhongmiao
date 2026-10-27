import SwiftUI

extension View {

    /// 凭据从“待验证/未配置”变成可用时，自动 reload 一次原生页。
    /// 冷启动的静默验证和设置页保存凭据都走这条路径。
    func refreshWhenIntegrationReady(
        center: IntegrationCenter,
        serviceID: String,
        action: @escaping () -> Void
    ) -> some View {
        onChange(of: center.state(for: serviceID)) { _, state in
            if state.isUsable {
                action()
            }
        }
    }
}
