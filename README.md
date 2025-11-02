# swift-api-client

モダンな async/await をサポートした軽量な Swift 製 HTTP API クライアントパッケージ

## 概要

`swift-api-client` は、Swift アプリケーションで HTTP API 呼び出しをシンプルかつ型安全に行うためのパッケージです。iOS および macOS プラットフォームに対応し、モダンな並行処理機能をサポートしています。

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

## 使い方

```swift
import APIClient

// 使用例
// ここに API クライアントの使用例を追加
```

## 機能

- ✅ モダンな async/await API
- ✅ 型安全なリクエスト/レスポンス処理
- ✅ iOS および macOS 対応
- ✅ 外部依存なしの軽量設計

## ライセンス

MIT License

Copyright (c) 2024 NOPROBLEM

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
