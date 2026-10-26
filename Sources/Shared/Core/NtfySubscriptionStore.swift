import Foundation
import ZhongmiaoCore

/// 独立 ntfy 订阅（不属于任何应用的主题）的持久化。
///
/// 单独用一个 UserDefaults key，而不是塞进 `AppSettings`：`AppSettings` 走合成 Codable，
/// 旧数据缺少新字段会让整份设置解码失败并被静默重置。订阅列表与设置互不影响，分开存更安全。
enum NtfySubscriptionStore {

    private static let key = "zhongmiao.ntfy.topics.v1"

    static func load() -> [String] {
        let raw = UserDefaults.standard.stringArray(forKey: key) ?? []
        var seen = Set<String>()
        return raw.compactMap { NtfyTopic.normalized($0) }
            .filter { seen.insert($0).inserted }
    }

    static func save(_ topics: [String]) {
        UserDefaults.standard.set(topics, forKey: key)
    }
}
