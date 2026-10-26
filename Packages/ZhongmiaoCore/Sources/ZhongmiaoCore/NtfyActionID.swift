import Foundation

/// ntfy 动作路由（`/{topic}/{id}/read`）里 id 的规则。
///
/// 服务端用 `[-_A-Za-z0-9]{1,64}` 校验每一个 id，只要有一个不合规整条请求就被拒，
/// 所以不合规的 id 必须在发请求前就被剔掉，不能混进批量请求。
public enum NtfyActionID {

    /// 单次批量请求最多带多少个 id —— 对应 fork 的 `/{topic}/{id1,id2,…}/read` 路由。
    public static let maxIDsPerRequest = 50

    /// 服务端接受的形式：1–64 位字母、数字、`-`、`_`。
    public static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= 64 else { return false }
        return id.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "-"), UInt8(ascii: "_"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"):
                return true
            default:
                return false
            }
        }
    }

    /// 寻址一条消息：优先用序列 id，没有就用消息 id。
    ///
    /// 普通消息的 `sequence_id` 与消息 id 相同且被服务端省略，所以消息 id 才是常态。
    /// 两个候选都非法时返回 nil —— 调用方应跳过这条，而不是让整批请求被服务端拒绝。
    public static func targetID(sequenceID: String?, messageID: String?) -> String? {
        let candidates = [sequenceID, messageID].compactMap { $0 }
        return candidates.first { isValid($0) }
    }

    /// 去掉非法与重复的 id，并按每批 `limit` 个切分。
    public static func chunks(_ ids: [String], limit: Int = maxIDsPerRequest) -> [[String]] {
        var seen = Set<String>()
        let valid = ids.filter { isValid($0) && seen.insert($0).inserted }
        let size = max(1, limit)
        guard !valid.isEmpty else { return [] }
        return stride(from: 0, to: valid.count, by: size).map { start in
            Array(valid[start..<min(start + size, valid.count)])
        }
    }
}
