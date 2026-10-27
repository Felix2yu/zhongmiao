import Foundation

public enum IntegrationDestination: Hashable, Sendable {
    case native
    case web
    case unconfigured
}

/// 首页/通知深链的唯一分流规则。
public enum IntegrationRouter {

    /// - Parameters:
    ///   - serviceID: 目标服务。
    ///   - hasExplicitURL: 通知里是否带具体页面地址。带地址时必须走网页，
    ///     否则会丢掉“打开某条记录”的语义。
    ///   - preferWeb: 用户在该应用设置里勾了“优先网页版”。
    ///   - hasNativeTarget: 通知里是否带原生条目目标（某条演出、某天日记…）。
    ///     带目标时优先走原生页，才能直接落到那一条。
    public static func resolve(
        serviceID: String,
        hasExplicitURL: Bool,
        preferWeb: Bool,
        hasNativeTarget: Bool = false
    ) -> IntegrationDestination {
        guard let definition = IntegrationCatalog.definition(for: serviceID) else {
            return .web
        }
        guard definition.priority != .web else { return .web }
        // 用户显式选了网页版，尊重它。
        if preferWeb { return .web }
        // 目标比地址更精确：能落到具体条目就别退回去看首页。
        if hasNativeTarget { return .native }
        if hasExplicitURL { return .web }
        return .native
    }
}
