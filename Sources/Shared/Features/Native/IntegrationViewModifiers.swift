import Observation
import SwiftUI

/// 原生页新增/编辑表单共用的提交状态。
///
/// 约定：同一时刻只允许一次提交；失败时表单不关闭、输入不丢、错误显示在表单内；
/// 成功后才由调用方关闭表单并刷新数据。
@MainActor
@Observable
final class FormSubmitState {

    private(set) var isSaving = false
    private(set) var error: String?

    func reset() {
        error = nil
    }

    /// 执行一次提交，返回是否成功。
    @discardableResult
    func run(_ action: @MainActor () async -> String?) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        error = nil
        let message = await action()
        isSaving = false
        error = message
        return message == nil
    }
}

extension View {

    /// 凭据从“待验证/未配置”变成可用时，自动 reload 一次原生页。
    /// 冷启动的静默验证和设置页保存凭据都走这条路径。
    func refreshWhenIntegrationReady(
        center: IntegrationCenter,
        serviceID: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        onChange(of: center.state(for: serviceID)) { _, state in
            if state.isUsable {
                action()
            }
        }
    }
}
