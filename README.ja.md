[English](./README.md) | 日本語

# swift-api-client

モダンな async/await をサポートした軽量な Swift 製 HTTP API クライアントパッケージ

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

📚 **[完全なドキュメント](https://no-problem-dev.github.io/swift-api-client/documentation/apiclient/)**

## 概要

`swift-api-client` は、Swift アプリケーションで HTTP API 呼び出しをシンプルかつ型安全に行うためのパッケージ。iOS および macOS プラットフォームに対応し、モダンな並行処理機能をサポートする。

[swift-api-contract](https://github.com/no-problem-dev/swift-api-contract) が定義する `APIContract` プロトコルをベースにしており、コンパイル時の型チェックでリクエスト/レスポンスの整合性を保証する。

### 主な機能

- **モダンな async/await API** - Swift 6.0 の並行処理機能をフル活用
- **型安全なリクエスト/レスポンス** - `APIContract` による コンパイル時の型チェック
- **自動 JSON デコーディング** - Codable を使った簡単なレスポンス処理
- **柔軟なエラーハンドリング** - カスタムエラーデコードをグループ単位で定義可能
- **認証サポート** - Bearer / ApiKey / QueryParam 認証をトークンプロバイダーで統合
- **HTTP イベントストリーム** - 認証エラー・レート制限等の重要イベントを AsyncStream で通知
- **HTTP ログストリーム** - 全リクエスト/レスポンスを AsyncStream で監視可能
- **SSE ストリーミング** - Server-Sent Events による型付き/生ストリームに対応
- **クロスプラットフォーム** - iOS および macOS 対応

## 依存パッケージ

| パッケージ | 用途 |
|---|---|
| [swift-api-contract](https://github.com/no-problem-dev/swift-api-contract) | API 契約の型定義（`APIContract` / `APIContractGroup` 等） |
| [swift-http-transport](https://github.com/no-problem-dev/swift-http-transport) | HTTP 送受信 / リトライ / SSE |
| [swift-structured-data](https://github.com/no-problem-dev/swift-structured-data) | JSON エンコード・デコード |

## 必要要件

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## インストール

### Swift Package Manager

`Package.swift` に以下を追加する：

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "2.3.1")
]
```

または Xcode で：
1. File > Add Package Dependencies
2. パッケージ URL を入力: `https://github.com/no-problem-dev/swift-api-client.git`
3. バージョンを選択: `2.3.1` 以降

## クイックスタート

このパッケージは `APIContract` プロトコルに適合した型でリクエストを定義する。

```swift
import APIClient
import APIContract

// 1. レスポンス型を定義
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

// 2. API グループを定義（共通設定）
enum UserAPI: APIContractGroup {
    static let basePath = "/v1"
    static let auth: AuthScheme = .bearer
    static let endpoints: [EndpointDescriptor] = []
    static func decodeError(
        statusCode: Int, data: Data,
        headers: [String: String], decoder: any APIBodyDecoder
    ) -> (any Error)? { nil }
}

// 3. エンドポイント契約を定義
struct GetUser: APIContract, APIInput {
    typealias Group = UserAPI
    typealias Input = Self
    typealias Output = User
    static let method: APIMethod = .get
    static let subPath = "/users/1"
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }
    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?, decoder: any APIBodyDecoder
    ) throws -> Self { Self() }
}

// 4. クライアントを作成してリクエストを実行
let client = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)
let response = try await client.executeWithResponse(GetUser())
print(response.output.name)  // User.name
```

## 使い方

### POST リクエスト（JSON ボディ付き）

```swift
struct CreateUserBody: Codable, Sendable {
    let name: String
    let email: String
}

struct CreateUser: APIContract, APIInput {
    typealias Group = UserAPI
    typealias Input = Self
    typealias Output = User
    static let method: APIMethod = .post
    static let subPath = "/users"
    let body: CreateUserBody
    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? {
        try encoder.encode(body)
    }
    static func decode(
        pathParameters: [String: String], queryParameters: [String: String],
        body: Data?, decoder: any APIBodyDecoder
    ) throws -> Self { fatalError("server-only") }
}

let response = try await client.executeWithResponse(
    CreateUser(body: CreateUserBody(name: "Ada", email: "ada@example.com"))
)
let newUser = response.output
```

### エラーハンドリング

```swift
do {
    let response = try await client.executeWithResponse(GetUser())
    print(response.output.name)
} catch APIError.unauthorized {
    print("認証エラー")
} catch APIError.networkError(let error) {
    print("ネットワークエラー: \(error.localizedDescription)")
} catch APIError.httpError(let statusCode, _) {
    print("HTTP エラー: \(statusCode)")
} catch APIError.decodingError(let error) {
    print("デコードエラー: \(error.localizedDescription)")
} catch {
    print("予期しないエラー: \(error)")
}
```

### 認証トークンの使用

```swift
// トークンプロバイダーを実装
struct MyTokenProvider: AuthTokenProvider {
    func fetchToken() async throws -> String? {
        // トークン取得ロジック（例：Keychain から取得）
        return "your-auth-token"
    }
}

// クライアント作成時にトークンプロバイダーを指定
let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    authTokenProvider: MyTokenProvider()
)
// リクエスト時に自動的に Authorization: Bearer ヘッダーが追加される
```

### バイナリレスポンス（音声・画像）

```swift
// executeRaw は JSON デコードせず生の Data を返す
let response = try await client.executeRaw(GetAudioContract())
let audioData = response.output  // Data
```

### SSE ストリーミング

型付きストリーム（単一イベント型の場合）：

```swift
for try await event in client.execute(StreamContract()) {
    print(event.delta)
}
```

生ストリーム（Anthropic など複数イベント型の場合）：

```swift
for try await sse in client.executeEventStream(GetStreamContract()) {
    print(sse.event ?? "message", sse.data)
}
```

### HTTP イベントの監視

重要な HTTP レスポンス（401, 403, 429, 503, 5xx）をアプリ全体で監視できる。

```swift
Task {
    for await event in client.events {
        switch event {
        case .unauthorized:
            await authManager.handleLogout()
        case .rateLimited(_, let retryAfter, _):
            print("レート制限: \(retryAfter ?? 0)秒後にリトライ")
        case .serviceUnavailable:
            await router.showMaintenanceScreen()
        default:
            break
        }
    }
}
```

### HTTP ログの監視

```swift
// デバッグ用コンソール出力（CustomStringConvertible による整形済み出力）
Task {
    for await log in client.logs {
        print(log)
    }
}

// カスタム処理（Analytics 送信など）
Task {
    for await log in client.logs {
        switch log {
        case .success(let endpoint, let statusCode, _):
            analytics.trackSuccess(endpoint: endpoint.path, statusCode: statusCode)
        case .httpError(let endpoint, let statusCode, _):
            analytics.trackError(endpoint: endpoint.path, statusCode: statusCode)
        case .decodingError(let endpoint, _, _, let targetType):
            analytics.trackDecodingError(endpoint: endpoint.path, type: targetType)
        }
    }
}
```

## ライセンス

MIT ライセンスの下で公開している。詳細は [LICENSE](LICENSE) ファイルを参照。

## サポート

問題の報告や機能リクエストは [GitHub Issues](https://github.com/no-problem-dev/swift-api-client/issues) へ。
