# 弾幕メーカー

ユーザーが弾幕ステージを作って投稿し、世界中で遊べる iOS ゲーム。仕様は `docs/SPEC.md`、ブラウザ試作は `docs/prototype.html`。

## 構成
- `DanmakuCore/` … シミュレーション本体（Swift Package。UIKit/SpriteKit 非依存）
- `DanmakuApp/` … SwiftUI アプリ本体
- `firebase/` … Cloud Functions（TypeScript）、ルール、Hosting
- `web-tests/` … Playwright テスト
- `project.yml` … XcodeGen 設定（`.xcodeproj` は生成物なので手で触らない）

## ビルドの仕方
XcodeGen は `~/.local/xcodegen-dl/xcodegen/bin/xcodegen` に置いてある。
```
~/.local/xcodegen-dl/xcodegen/bin/xcodegen generate
open DanmakuMaker.xcodeproj
```
Xcode で iPhone 実機をつなぎ、スキーム `DanmakuApp` を実行する（このプロジェクトは実機確認が基本）。

## テストの回し方
```
cd DanmakuCore && swift test
```
Functions / ルール / Playwright のテストはフェーズ5以降で追加する。

## エミュレーターの起動
フェーズ5で追加する（`firebase emulators:start`）。
