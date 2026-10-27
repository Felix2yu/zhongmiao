import Foundation

/// 原生页内的某一个条目。
///
/// 点通知时如果只带服务 ID，落点就是应用首页——「明天有场演出」提醒点进去
/// 还要自己再找一遍。带上目标就能直接打开那一条。
/// `kind` 由各应用自己解释（"record" / "diary" / "plant" / "task" …），
/// `identifier` 是主键、日期串或路径片段。
public struct NativeTarget: Hashable, Sendable, Codable {

    public var kind: String
    public var identifier: String

    public init(kind: String, identifier: String) {
        self.kind = kind
        self.identifier = identifier
    }

    public var isEmpty: Bool {
        kind.isEmpty || identifier.isEmpty
    }
}

/// 目标在通知 `userInfo` 里的键名。与 `integrationServiceID` 同一套约定。
public enum NativeTargetKeys {

    public static let kind = "integrationTargetKind"
    public static let identifier = "integrationTargetID"

    public static func userInfo(for target: NativeTarget) -> [String: String] {
        [kind: target.kind, identifier: target.identifier]
    }

    /// 从通知的 userInfo 里还原目标。缺一不可，否则视为没有目标。
    public static func target(from userInfo: [AnyHashable: Any]) -> NativeTarget? {
        guard let kind = userInfo[kind] as? String, !kind.isEmpty,
              let identifier = userInfo[identifier] as? String, !identifier.isEmpty
        else { return nil }
        return NativeTarget(kind: kind, identifier: identifier)
    }
}
