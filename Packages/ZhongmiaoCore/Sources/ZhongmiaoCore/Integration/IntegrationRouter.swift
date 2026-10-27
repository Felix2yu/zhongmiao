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
    public static func resolve(
        serviceID: String,
        hasExplicitURL: Bool,
        preferWeb: Bool
    ) -> IntegrationDestination {
        guard let definition = IntegrationCatalog.definition(for: serviceID) else {
            return .web
        }
        guard definition.priority != .web else { return .web }
        if hasExplicitURL { return .web }
        if preferWeb { return .web }
        return .native
    }
}
