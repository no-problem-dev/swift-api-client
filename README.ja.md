[English](./README.md) | 日本語

# swift-api-client

API と食い違った呼び出しをコンパイル時に弾き、認証・リトライ・エラー通知を、通常応答でもストリーミングでも一度書けば済ませる Swift 向け HTTP クライアント。

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+%20%7C%20Linux-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

## 概要

エンドポイントは [swift-api-contract](https://github.com/no-problem-dev/swift-api-contract) の
`APIContract` に適合する型として宣言する。メソッド・パス・ボディ・出力型が契約に乗るので、
呼び出し側がそのエンドポイントの返さない形を要求することはできなくなる。

クライアント自身は I/O を持たない。送受信は差し替えられるトランスポートなので、テストでは
モックを差せば URL の組み立てとヘッダーの優先順位まで本物の経路を通せる。リトライとレート制限は
その周りのデコレータで、JSON の直列化は固定であり、コーダーを渡すのではなく `keyStyle` と
`dateStrategy` で設定する。

- バッファ応答と SSE がひとつのトランスポート・コーデック・資格情報を共有するので、両者がずれない
- 認証はリクエストごとに、自分で実装したトークンプロバイダーが解決する
- 401 / 403 / 429 / 503 とその他の 5xx はアプリ全体の `AsyncStream` にも流れるので、ログアウトやメンテナンス画面は一度書けばよい
- エラーデコードをグループ単位で定義でき、API 独自のエラーボディを自前の Swift エラー型にできる
- `Retry-After` を尊重するバックオフ付きリトライ

## クイックスタート

```swift
import APIClient

let client = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!,
    keyStyle: .snakeCase
)

let product = try await client.execute(GetProduct(id: "sku-42"))

for try await chunk in client.execute(StreamCompletion(prompt: prompt)) {
    transcript.append(chunk.delta)
}
```

`GetProduct` と `StreamCompletion` は契約。契約の宣言方法、API のエラーを Swift のエラーへ
対応づける方法、イベントストリームの購読は、いずれもドキュメントにある。

## ドキュメント

**[API リファレンスとガイド](https://no-problem-dev.github.io/swift-api-client/documentation/apiclient/)** —
契約の宣言から、401 をアプリ全体で一度だけ処理するところまでの通しの解説。

## 必要要件

iOS 17.0+ · macOS 14.0+ · Linux · Swift 6.0+

## インストール

`Package.swift` に追加する:

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "3.0.0")
]
```

または Xcode で **File > Add Package Dependencies** を開き、
`https://github.com/no-problem-dev/swift-api-client.git` を入力する。

## コントリビュート

[CONTRIBUTING.md](CONTRIBUTING.md) を参照。

## ライセンス

MIT。詳細は [LICENSE](LICENSE)。
