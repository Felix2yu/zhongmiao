import Foundation

/// 指数退避（带抖动），用于通知拉取与推送投递的重试。
///
/// 抖动的随机源显式注入，便于测试确定性；App 里传 `Double.random(in:)`。
public struct RetryPolicy: Sendable, Equatable {
    public var base: TimeInterval
    public var maximum: TimeInterval
    public var multiplier: Double
    /// 抖动比例（0…1）。实际延迟落在 `[delay * (1 - jitter), delay]`。
    public var jitter: Double

    public init(base: TimeInterval = 2, maximum: TimeInterval = 300, multiplier: Double = 2, jitter: Double = 0.2) {
        self.base = base
        self.maximum = maximum
        self.multiplier = multiplier
        self.jitter = jitter
    }

    public static let standard = RetryPolicy()

    /// - Parameters:
    ///   - attempt: 从 1 开始的失败次数。
    ///   - randomUnit: 0…1 的随机数，测试时传固定值。
    public func delay(forAttempt attempt: Int, randomUnit: Double = Double.random(in: 0...1)) -> TimeInterval {
        let clampedAttempt = max(1, attempt)
        let exponential = base * pow(multiplier, Double(clampedAttempt - 1))
        let capped = min(exponential, maximum)
        guard jitter > 0 else { return capped }
        let upper = capped
        let lower = capped * (1 - min(jitter, 1))
        return lower + (upper - lower) * min(max(randomUnit, 0), 1)
    }

    /// 是否应该继续重试（连续失败达到上限后转为"等下次前台同步"）。
    public func shouldRetry(attempt: Int, limit: Int = 6) -> Bool {
        attempt < limit
    }
}
