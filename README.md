# swift-api-client

モダンな async/await をサポートした軽量な Swift 製 HTTP API クライアントパッケージ

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 概要

`swift-api-client` は、Swift アプリケーションで HTTP API 呼び出しをシンプルかつ型安全に行うためのパッケージです。iOS および macOS プラットフォームに対応し、モダンな並行処理機能をサポートしています。

### 主な機能

- ✅ **モダンな async/await API** - Swift 6.0 の並行処理機能をフル活用
- ✅ **型安全なリクエスト/レスポンス** - コンパイル時の型チェックで安全性を保証
- ✅ **自動 JSON デコーディング** - Codable を使った簡単なレスポンス処理
- ✅ **柔軟なエラーハンドリング** - 詳細なエラー情報を提供
- ✅ **認証サポート** - トークンプロバイダーによる認証統合
- ✅ **HTTP ロギング** - リクエスト/レスポンスのデバッグ機能
- ✅ **ゼロ依存** - 外部ライブラリを使わない軽量設計
- ✅ **クロスプラットフォーム** - iOS および macOS 対応

## 必要要件

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## インストール

### Swift Package Manager

`Package.swift` に以下を追加してください：

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "1.0.0")
]
```

または Xcode で：
1. File > Add Package Dependencies
2. パッケージ URL を入力: `https://github.com/no-problem-dev/swift-api-client.git`
3. バージョンを選択: `1.0.0` 以降

## クイックスタート

最もシンプルな使用例：

```swift
import APIClient

// API クライアントを作成
let client = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)

// エンドポイントを定義
let endpoint = APIEndpoint(
    path: "/users/123",
    method: .get
)

// リクエストを実行
let data = try await client.request(endpoint)
```

## 使い方

### 基本的な GET リクエスト

```swift
import APIClient

// レスポンス型を定義
struct User: Codable {
    let id: String
    let name: String
    let email: String
}

// API クライアントを作成
let client = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)

// エンドポイントを定義
let endpoint = APIEndpoint(
    path: "/users/123",
    method: .get
)

// リクエストを実行してデコード
let user: User = try await client.request(endpoint)
print(user.name)
```

### POST リクエスト（JSON ボディ付き）

```swift
struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

let requestBody = CreateUserRequest(name: "John Doe", email: "john@example.com")
let jsonData = try JSONEncoder().encode(requestBody)

let endpoint = APIEndpoint(
    path: "/users",
    method: .post,
    headers: ["Content-Type": "application/json"],
    body: jsonData
)

let newUser: User = try await client.request(endpoint)
```

### クエリパラメータ付きリクエスト

```swift
let endpoint = APIEndpoint(
    path: "/users",
    method: .get,
    queryItems: [
        URLQueryItem(name: "page", value: "1"),
        URLQueryItem(name: "limit", value: "20")
    ]
)

let users: [User] = try await client.request(endpoint)
```

### エラーハンドリング

```swift
do {
    let user: User = try await client.request(endpoint)
    print("Success: \(user.name)")
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
class MyTokenProvider: AuthTokenProvider {
    func getToken() async throws -> String? {
        // トークン取得ロジック（例：Keychain から取得）
        return "your-auth-token"
    }
}

// クライアント作成時にトークンプロバイダーを指定
let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    authTokenProvider: MyTokenProvider()
)

// リクエスト時に自動的に Authorization ヘッダーが追加されます
let user: User = try await client.request(endpoint)
```

### HTTP ロギングの有効化

```swift
// デバッグ時にリクエスト/レスポンスをログ出力
let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    enableLogging: true
)
```

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。詳細は [LICENSE](LICENSE) ファイルをご覧ください。

## サポート

問題が発生した場合や機能リクエストがある場合は、[GitHub の Issue](https://github.com/no-problem-dev/swift-api-client/issues) を作成してください。
