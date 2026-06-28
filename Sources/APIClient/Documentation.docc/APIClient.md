# ``APIClient``

Transport・認証・直列化を分離した薄い HTTP API クライアント基盤。

## Overview

`APIClient` パッケージは、iOS/macOS アプリと REST/SSE バックエンドをつなぐ薄い
Orchestrator レイヤー。Transport(HTTP 送受信)・Codec(JSON 直列化)・
Resilience(リトライ/レート制限)の 3 関心を分離し、``APIClientImpl`` という
単一の実装型で統合する。

コントラクト駆動設計（`APIContract` パッケージ）と組み合わせることで、
エンドポイント定義からリクエスト組み立て・デコード・エラーマッピングまでを
型安全に処理する。非ストリーミング（`executeWithResponse` / `executeRaw`）と
SSE ストリーミング（`execute` / `executeEventStream`）を同一 Transport・Codec で
対称に提供する。

### 基本的な使い方

``APIClientImpl`` を生成し、`APIContract` 準拠型を渡して実行する。
キーが `snake_case` の REST API なら `keyStyle: .snakeCase` を渡すだけで、
エンコード・デコード両方に対称に適用される。

```swift
import APIClient

let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    keyStyle: .snakeCase
)
```

### イベント監視

401/429 などのクロスカット関心事は `client.events` ストリームで一元購読できる。
ログアウト遷移・レート制限 UI をイベント駆動で実装できる。

```swift
Task {
    for await event in client.events {
        switch event {
        case .unauthorized:
            await authManager.handleLogout()
        case .rateLimited(_, let retryAfter, _):
            scheduleRetry(after: retryAfter)
        default:
            break
        }
    }
}
```

## Topics

### 基本型

- ``APIClientImpl``
- ``APIClient``

### 認証

- ``AuthTokenProvider``
- ``ScopedAuthTokenProvider``

### 設定

- ``APIKeyStyle``
- ``DateStrategy``

### エラーとテレメトリ

- ``APIError``
- ``HTTPEvent``
- ``HTTPLog``
- ``APIEndpoint``
