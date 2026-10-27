import SwiftUI
import ZhongmiaoCore

private struct NativeTargetEnvironmentKey: EnvironmentKey {
    static let defaultValue: NativeTarget? = nil
}

extension EnvironmentValues {
    /// 点通知进来时，要直接打开原生页里的哪一条。
    /// 没有目标就是普通进入，页面按默认视图展示。
    var nativeTarget: NativeTarget? {
        get { self[NativeTargetEnvironmentKey.self] }
        set { self[NativeTargetEnvironmentKey.self] = newValue }
    }
}
