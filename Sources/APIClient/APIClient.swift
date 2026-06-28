@_exported import APIContract
@_exported import HTTPTransport
import Foundation
import StructuredDataCore

/// HTTPベースのAPIクライアントプロトコル。
///
/// 非ストリーミング(`executeWithResponse`/`execute`)とストリーミング(`execute` →
/// `AsyncThrowingStream`)を同一の Transport・Codec で対称に提供する。
public protocol APIClient: APIExecutable, StreamingAPIExecutable {
    /// `Encodable` 値を内部 Codec で JSON エンコードする。
    ///
    /// カスタムリクエストボディを手動構築する場合など、クライアントの
    /// 直列化設定（`keyStyle` / `dateStrategy`）を一貫して使いたい際に利用する。
    ///
    /// - Parameter value: エンコード対象の値
    /// - Returns: JSON エンコード済みの `Data`
    /// - Throws: エンコード失敗時に `EncodingError`
    func encode<T: Encodable>(_ value: T) throws -> Data

    /// 横断的 HTTP イベント（401 / 403 / 429 / 503 / 5xx）を流す `AsyncStream`。
    ///
    /// ログアウト遷移・メンテナンス画面・レート制限 UI などをイベント駆動で実装するために使う。
    var events: AsyncStream<HTTPEvent> { get }

    /// 全リクエスト/レスポンスのログエントリを流す `AsyncStream`。
    ///
    /// デバッグ出力や Analytics 送信など、リクエスト横断の監視基盤として使う。
    var logs: AsyncStream<HTTPLog> { get }
}

/// 日付ワイヤ形式の指定（内部 Codec の中立 enum を再公開）。
public typealias DateStrategy = DateCodingStrategy

/// JSON オブジェクトキーの変換スタイル。
///
/// `APIClientImpl` の `keyStyle:` 引数で指定する。エンコード（リクエストボディ）と
/// デコード（レスポンスボディ）の両方に対称に適用される。
///
/// - `default`: Swift のプロパティ名をそのまま使う（`camelCase`）
/// - `snakeCase`: `camelCase` → `snake_case` に変換（多くの REST API のデフォルト）
/// - `kebabCase`: `camelCase` → `kebab-case` に変換
public enum APIKeyStyle: Sendable {
    case `default`
    case snakeCase
    case kebabCase

    var encoding: EncodingOptions.KeyStrategy {
        switch self {
        case .default: return .useDefaultKeys
        case .snakeCase: return .convertToSnakeCase
        case .kebabCase: return .convertToKebabCase
        }
    }

    var decoding: DecodingOptions.KeyStrategy {
        switch self {
        case .default: return .useDefaultKeys
        case .snakeCase: return .convertFromSnakeCase
        case .kebabCase: return .convertFromKebabCase
        }
    }
}
