import Foundation

/// HTTPイベントのストリームソース
///
/// 複数の購読者に対して同じイベントを配信するマルチキャスト機能を提供します。
/// 各購読者は独立した`AsyncStream`を取得し、それぞれのライフサイクルで購読を管理できます。
///
/// ## 使用例
/// ```swift
/// let eventSource = HTTPEventSource()
///
/// // 購読者1: 認証エラー監視
/// Task {
///     for await event in await eventSource.events {
///         if case .unauthorized = event {
///             await handleLogout()
///         }
///     }
/// }
///
/// // 購読者2: サーバーエラー監視
/// Task {
///     for await event in await eventSource.events {
///         if case .serverError = event {
///             await showErrorScreen()
///         }
///     }
/// }
///
/// // イベント発行（内部用）
/// await eventSource.emit(.unauthorized(endpoint: endpoint, data: data))
/// ```
public actor HTTPEventSource {
    /// 購読者のContinuationを管理
    private var subscriptions: [UUID: AsyncStream<HTTPEvent>.Continuation] = [:]

    /// 初期化
    public init() {}

    /// 新しいイベントストリームを取得
    ///
    /// 呼び出しごとに独立した`AsyncStream`を返します。
    /// 複数箇所から購読しても、それぞれが同じイベントを受信できます。
    ///
    /// ストリームは購読者のTaskがキャンセルされると自動的にクリーンアップされます。
    ///
    /// - Returns: HTTPイベントの非同期ストリーム
    public var events: AsyncStream<HTTPEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: HTTPEvent.self, bufferingPolicy: .unbounded)
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

    /// イベントを全購読者に発行
    ///
    /// 登録されているすべての購読者にイベントを配信します。
    /// 購読者がいない場合、イベントは単純に破棄されます。
    ///
    /// - Parameter event: 発行するHTTPイベント
    func emit(_ event: HTTPEvent) {
        for continuation in subscriptions.values {
            continuation.yield(event)
        }
    }
}
