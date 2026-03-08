import Foundation

/// リトライポリシー
public protocol RetryPolicy: Sendable {
    var maxRetries: Int { get }
    func shouldRetry(statusCode: Int, attempt: Int) -> Bool
    func delay(for attempt: Int, retryAfter: TimeInterval?) -> TimeInterval
}

/// 指数バックオフリトライポリシー
public struct ExponentialBackoff: RetryPolicy, Sendable {
    public let maxRetries: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitter: Double

    public init(
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        jitter: Double = 0.1
    ) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    public static let `default` = ExponentialBackoff()

    public static let aggressive = ExponentialBackoff(
        maxRetries: 10, baseDelay: 0.5, maxDelay: 120.0, jitter: 0.2
    )

    public static let conservative = ExponentialBackoff(
        maxRetries: 3, baseDelay: 2.0, maxDelay: 30.0, jitter: 0.1
    )

    public func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        guard attempt < maxRetries else { return false }
        return [429, 500, 502, 503, 504].contains(statusCode)
    }

    public func delay(for attempt: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter { return retryAfter }
        let exponential = min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
        let jitterValue = exponential * Double.random(in: 0...jitter)
        return exponential + jitterValue
    }
}

/// リトライなしポリシー
public struct NoRetry: RetryPolicy, Sendable {
    public init() {}
    public let maxRetries: Int = 0
    public func shouldRetry(statusCode: Int, attempt: Int) -> Bool { false }
    public func delay(for attempt: Int, retryAfter: TimeInterval?) -> TimeInterval { 0 }
}
