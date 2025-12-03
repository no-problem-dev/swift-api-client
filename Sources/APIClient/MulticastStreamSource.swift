import Foundation

/// マルチキャストストリームソース
///
/// 複数の購読者に対して同じ要素を配信するジェネリックなストリームソースです。
/// 各購読者は独立した`AsyncStream`を取得し、それぞれのライフサイクルで購読を管理できます。
///
/// ## 使用例
/// ```swift
/// let source = MulticastStreamSource<MyEvent>()
///
/// // 購読者1
/// Task {
///     for await event in await source.stream {
///         print("Subscriber 1: \(event)")
///     }
/// }
///
/// // 購読者2
/// Task {
///     for await event in await source.stream {
///         print("Subscriber 2: \(event)")
///     }
/// }
///
/// // 発行（両方の購読者が受信）
/// await source.emit(MyEvent())
/// ```
public actor MulticastStreamSource<Element: Sendable> {
    /// 購読者のContinuationを管理
    private var subscriptions: [UUID: AsyncStream<Element>.Continuation] = [:]

    /// 初期化
    public init() {}

    /// 新しいストリームを取得
    ///
    /// 呼び出しごとに独立した`AsyncStream`を返します。
    /// 複数箇所から購読しても、それぞれが同じ要素を受信できます。
    ///
    /// ストリームは購読者のTaskがキャンセルされると自動的にクリーンアップされます。
    ///
    /// - Returns: 要素の非同期ストリーム
    public var stream: AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: .unbounded)
        subscriptions[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { [weak self] in
                await self?.unsubscribe(id)
            }
        }
        return stream
    }

    /// 購読を解除
    private func unsubscribe(_ id: UUID) {
        _ = subscriptions.removeValue(forKey: id)
    }

    /// 要素を全購読者に発行
    ///
    /// 登録されているすべての購読者に要素を配信します。
    /// 購読者がいない場合、要素は単純に破棄されます。
    ///
    /// - Parameter element: 発行する要素
    func emit(_ element: Element) {
        for continuation in subscriptions.values {
            continuation.yield(element)
        }
    }
}
