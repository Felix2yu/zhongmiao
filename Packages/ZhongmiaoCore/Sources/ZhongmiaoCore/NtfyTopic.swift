import Foundation

/// 独立 ntfy 订阅的主题标识。
///
/// 众妙既能给每个应用配一个主题，也允许在「ntfy 主题」里单独订阅服务器上的主题。
/// 后者没有对应的应用 id，于是用 `ntfy:<topic>` 作为伪服务 id：
///
/// - 游标按服务 id 分开，多个主题互不干扰；
/// - 去重键天然带主题前缀，两个主题里同 id 的消息不会互相吞掉；
/// - 收件箱据此把来源显示成主题名，而不是笼统的「ntfy」。
public enum NtfyTopic {

    /// 伪服务 id 前缀。用 `:` 是因为 ntfy 主题名不允许该字符，不会歧义。
    public static let servicePrefix = "ntfy:"

    /// ntfy 服务端限制：1–64 位，只允许字母、数字、`-`、`_`。
    public static let maximumLength = 64

    public static func serviceID(for topic: String) -> String {
        servicePrefix + topic
    }

    /// 从伪服务 id 取回主题名；普通服务 id 返回 nil。
    public static func topic(fromServiceID id: String) -> String? {
        guard id.hasPrefix(servicePrefix) else { return nil }
        let topic = String(id.dropFirst(servicePrefix.count))
        return topic.isEmpty ? nil : topic
    }

    public static func isStandaloneServiceID(_ id: String) -> Bool {
        topic(fromServiceID: id) != nil
    }

    /// 规范化用户输入：去掉首尾空白，非法字符或超长返回 nil。
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValid(trimmed) ? trimmed : nil
    }

    public static func isValid(_ topic: String) -> Bool {
        guard (1...maximumLength).contains(topic.count) else { return false }
        for scalar in topic.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x2D, 0x5F:
                continue
            default:
                return false
            }
        }
        return true
    }

    /// 校验失败时给用户看的原因；合法时返回 nil。
    public static func validationMessage(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "主题名不能为空"
        }
        if trimmed.count > maximumLength {
            return "主题名最多 \(maximumLength) 个字符"
        }
        if !isValid(trimmed) {
            return "只能用字母、数字、- 和 _，不能有空格或斜杠"
        }
        return nil
    }
}
