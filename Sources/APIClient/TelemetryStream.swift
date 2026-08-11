import Foundation

/// A telemetry channel every observer reads in full, and that keeps nothing for nobody.
///
/// Iterating gives each observer its own buffer fed from the same source, so a second
/// observer receives copies of what the first one sees instead of taking events away from
/// it. Iterate it as you would any `AsyncSequence`:
///
/// ```swift
/// Task {
///     for await event in client.events {
///         // Update the UI.
///     }
/// }
/// ```
///
/// Two properties worth designing around, both the opposite of an unbounded single-consumer
/// `AsyncStream`:
///
/// - **Nothing is retained for an observer that does not exist.** Events emitted before you
///   started iterating are gone; you see what is emitted from then on. A client nobody
///   observes holds no response bodies at all.
/// - **Each observer's buffer is bounded** at ``bufferLimit`` entries. An observer that
///   stops consuming loses its oldest events rather than growing without limit.
public struct TelemetryStream<Element: Sendable>: AsyncSequence, Sendable {
    /// How many entries one observer may fall behind before its oldest are dropped.
    public static var bufferLimit: Int { 256 }

    public typealias AsyncIterator = AsyncStream<Element>.Iterator

    private let observers: TelemetryObservers<Element>

    init(_ observers: TelemetryObservers<Element>) {
        self.observers = observers
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        observers.subscribe(limit: Self.bufferLimit).makeAsyncIterator()
    }
}

/// The observers of one channel, and the delivery of an element to all of them.
///
/// A lock rather than an actor, so that subscribing is synchronous: an observer that has
/// to `await` its way onto the channel would miss whatever is emitted while it waits.
final class TelemetryObservers<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    func subscribe(limit: Int) -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Element.self, bufferingPolicy: .bufferingNewest(limit)
        )
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            lock.withLock { _ = continuations.removeValue(forKey: id) }
        }
        lock.withLock { continuations[id] = continuation }
        return stream
    }

    func yield(_ element: Element) {
        let observers = lock.withLock { Array(continuations.values) }
        for continuation in observers { continuation.yield(element) }
    }

    deinit {
        for continuation in continuations.values { continuation.finish() }
    }
}
