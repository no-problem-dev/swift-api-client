# Changelog

このプロジェクトのすべての重要な変更は、このファイルに記録されます。

このフォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

## [未リリース]

なし

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

[未リリース]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.4...HEAD
[1.0.4]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.3...v1.0.4
[1.0.3]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.1...v1.0.3
[1.0.1]: https://github.com/no-problem-dev/swift-api-client/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/no-problem-dev/swift-api-client/releases/tag/v1.0.0

<!-- Auto-generated on 2025-11-09T05:04:46Z by release workflow -->
