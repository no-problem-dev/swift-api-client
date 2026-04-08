# Changelog

このプロジェクトのすべての重要な変更は、このファイルに記録されます。

このフォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

## [未リリース]

## [1.0.13] - 2026-01-11

### 追加

- **SSEストリーミングクライアント**: Server-Sent Events (SSE) クライアント実装
  - `SSEEvent`: SSEイベント構造体（data, event, id, retry フィールド）
  - `SSEClient`: SSEストリーミング操作プロトコル
  - `SSEClientImpl`: URLSessionベースのSSEクライアント実装（自動再接続対応）
  - `SSEClient+StreamingAPI`: `StreamingAPIContract` との連携拡張

### テスト

- SSEイベントパーシングのテストを追加
- SSEクライアント機能のテストを追加

## [1.0.12] - 2026-01-03

### 追加
- ユニットテストを追加

## [1.0.11] - 2026-01-03

### 変更
- **APIExecutable 統合**
  - `APIClient` プロトコルが `APIExecutable` を継承
  - `request()` メソッド削除（`execute()` のみに統一）
  - `HTTPMethod` → `APIMethod` に統一（api-contract 対応）
- Swift 6.2 に更新
- 不要なコメント・MARK を削除

### 破壊的変更
- `request()` メソッドは削除されました
  - 代わりに `execute()` を使用してください

## [1.0.10] - 2026-01-01

### 変更
- `HTTPMethod` → `APIMethod` にリネーム（api-contract v1.0.2 対応）

## [1.0.9] - 2025-12-31

### 追加
- **APIContract 統合**
  - `swift-api-contract` 1.0.0 を依存に追加（`.upToNextMajor`）
  - `APIClient` プロトコルが `APIExecutor` を継承
  - `execute<E: APIContract>()` メソッドを `APIClientImpl` に実装
  - `@_exported import` で利用側が `APIContract` を直接使用可能に

### 変更
- `HTTPMethod` の重複定義を削除（`APIContract` のものを使用）

### 破壊的変更
- `HTTPMethod` は `APIContract` モジュールからインポートされる形に変更
  - 既存コードは `import APIClient` のみで動作（`@_exported` により自動インポート）

## [1.0.8] - 2025-12-05

### 変更
- **ストリーム設計の簡素化**: マルチキャストからユニキャストへ変更
  - `MulticastStreamSource.swift` を削除
  - `AsyncStream.makeStream()` を直接使用するシンプルな実装に
  - Actor排除により `await` が不要に（パフォーマンス向上）
  - `stream`/`continuation` の標準命名パターンを採用

### 削除
- `MulticastStreamSource<Element>` を削除

### 破壊的変更
- `events`/`logs` プロパティから `async` を削除
  - 変更前: `for await event in await client.events`
  - 変更後: `for await event in client.events`
- 複数購読は非サポート（DIコンテナで単一購読を推奨）

## [1.0.7] - 2025-12-03

### 追加
- **HTTPイベントストリーム機能**
  - `HTTPEvent`: 重要なHTTPレスポンス（401, 403, 429, 503, 5xx）を表すイベント型
  - `APIClient.events`: 複数購読可能なイベントストリームプロパティ
  - 認証エラー、レート制限、サービス停止等をアプリ全体で一元的にハンドリング可能に
- **HTTPログストリーム機能**
  - `HTTPLog`: リクエスト/レスポンスのログエントリ型（CustomStringConvertible対応）
  - `APIClient.logs`: 複数購読可能なログストリームプロパティ
  - `print(log)`で整形済みログを簡単に出力可能
- **MulticastStreamSource<Element>**
  - 汎用的なマルチキャストAsyncStreamソース（Actor実装）
  - 複数購読者への同時配信、自動クリーンアップをサポート

### 削除
- `HTTPLogger`クラスを削除（`logs`ストリームに置き換え）
- `enableDebugLog`パラメータを削除

## [1.0.6] - 2025-11-15

### 追加
- `APIClientImpl`に`dateEncodingStrategy`パラメータを追加
  - `JSONEncoder.DateEncodingStrategy`を指定可能に（デフォルト: `.iso8601`）
  - バックエンドAPI（Go）のRFC3339形式に対応
  - リクエストボディの日付フィールドを正しくエンコード可能に
- `encode<T: Encodable>`メソッドを追加
  - リクエストボディのJSON文字列生成に統一的な日付エンコーディング戦略を適用
  - デバッグ時のログ出力で日付形式の一貫性を保証

### 変更
- リクエストボディのエンコーディングロジックをリファクタリング
  - 従来の`JSONEncoder()`直接使用から`encode`メソッド経由に統一
  - すべてのPOST/PUT/PATCHリクエストで日付エンコーディング戦略を適用

## [1.0.5] - 2025-11-13

### 追加
- `APIClientImpl`に`keyDecodingStrategy`パラメータを追加
  - `JSONDecoder.KeyDecodingStrategy`を指定可能に（デフォルト: `.useDefaultKeys`）
  - スネークケースAPIレスポンス対応のため`.convertFromSnakeCase`を指定可能
  - 後方互換性を保持しながら、柔軟なキー変換に対応

## [1.0.4] - 2025-11-09

### 修正
- 自動リリースワークフローのメッセージを完全に日本語に統一（PRディスクリプション、リリースノート、ログメッセージ）

## [1.0.3] - 2025-11-04

### 追加
- DocC ドキュメントの自動生成と GitHub Pages への公開機能を追加
  - Swift DocC Plugin を依存関係に追加
  - GitHub Actions ワークフローで自動的にドキュメントを生成・デプロイ
  - README に完全なドキュメントへのリンクを追加 (https://no-problem-dev.github.io/swift-api-client/documentation/apiclient/)

### 変更
- ドキュメントへのアクセシビリティを向上

## [1.0.1] - 2025-02-11

### 改善
- README に包括的な使用例とバッジを追加
  - Swift 6.0、プラットフォーム、SPM、ライセンスのバッジを追加
  - プレースホルダーコメントを実際の動作するコード例に置き換え
  - 最速のオンボーディングのためのクイックスタートセクションを追加
  - 基本的な GET リクエストの例を追加
  - POST リクエスト（JSON ボディ付き）の例を追加
  - クエリパラメータ付きリクエストの例を追加
  - 包括的なエラーハンドリングの例を追加
  - 認証トークンの使用例を追加
  - HTTP ロギングの有効化例を追加
  - LICENSE ファイルへの簡潔な参照を追加

### 追加
- MIT ライセンス情報を含む別の LICENSE ファイルを作成

### 変更
- README から完全なライセンステキストを削除し、LICENSE ファイルへの参照に置き換え

## [1.0.0] - 2024-12-XX

### 追加
- 初回リリース
- モダンな async/await API
- 型安全なリクエスト/レスポンス
- 自動 JSON デコーディング
- 柔軟なエラーハンドリング
- 認証サポート
- HTTP ロギング機能
- iOS 17.0+ および macOS 14.0+ サポート

[未リリース]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.13...HEAD
[1.0.13]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.12...v1.0.13
[1.0.12]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.11...v1.0.12
[1.0.11]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.10...v1.0.11
[1.0.10]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.9...v1.0.10
[1.0.9]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.8...v1.0.9
[1.0.8]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.7...v1.0.8
[1.0.7]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.6...v1.0.7
[1.0.6]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.5...v1.0.6
[1.0.5]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.4...v1.0.5
[1.0.4]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.1...v1.0.3
[1.0.1]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/no-problem-dev/swift-api-client/releases/tag/v1.0.0

<!-- Auto-generated on 2025-11-15T01:10:00Z by release workflow -->

<!-- Auto-generated on 2025-11-15T01:09:07Z by release workflow -->

<!-- Auto-generated on 2025-12-03T05:39:36Z by release workflow -->

<!-- Auto-generated on 2025-12-04T23:24:03Z by release workflow -->

<!-- Auto-generated on 2025-12-31T03:17:18Z by release workflow -->

<!-- Auto-generated on 2026-01-01T05:56:21Z by release workflow -->

<!-- Auto-generated on 2026-01-03T00:13:58Z by release workflow -->

<!-- Auto-generated on 2026-01-03T01:21:12Z by release workflow -->

<!-- Auto-generated on 2026-01-11T13:32:41Z by release workflow -->
