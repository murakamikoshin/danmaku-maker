# 弾幕メーカー

ユーザーが弾幕ステージを作って投稿し、世界中で遊べる iOS ゲーム。仕様は `docs/SPEC.md`、ブラウザ試作は `docs/prototype.html`。

## 構成
- `DanmakuCore/` … シミュレーション本体（Swift Package。UIKit/SpriteKit 非依存）。`StageBot`（公式ステージ検証ボット）もここ
- `DanmakuApp/` … SwiftUI アプリ本体（SpriteKit のプレイ画面、エディタ、一覧、広告・課金）
- `firebase/` … Cloud Functions（TypeScript）、Firestore / Storage ルール、Hosting（共有ページ・規約）
- `web-tests/` … Playwright の E2E テスト
- `tools/` … 公式ステージ生成・OGP 確認・Playwright 用スクリプト
- `project.yml` … XcodeGen 設定（`.xcodeproj` は生成物。Xcode Cloud が読めるようコミットしてある）
- `docs/` … 仕様、公式ステージ一覧（`OFFICIAL_STAGES.md`）、ストア文言（`APPSTORE_METADATA.md`）、提出チェックリスト（`SUBMISSION_CHECKLIST.md`）

## ビルドの仕方
XcodeGen は `~/.local/xcodegen-dl/xcodegen/bin/xcodegen` に置いてある（Homebrew なしで導入）。
```
~/.local/xcodegen-dl/xcodegen/bin/xcodegen generate
open DanmakuMaker.xcodeproj
```
`DanmakuApp/GoogleService-Info.plist`（Firebase の設定。Git には入れない）が必要。無いとオフライン動作（サンプルだけ遊べる）になる。
実機: iPhone をつないで、スキームを `DanmakuApp` にして実行。Debug ビルドは AdMob のテスト広告を使う。

## テストの回し方
```
# DanmakuCore（計算・リプレイ・試作との照合・公式ステージの整合性）
cd DanmakuCore && swift test

# 公式ステージの自動プレイ検証（弱いボット/強いボット）
cd DanmakuCore && swift build -c release && .build/release/StageBot ../DanmakuApp/Resources/official_stages.json

# Functions（ESLint・型・単体）
cd firebase/functions && npm run lint && npm test
# ルール・関数をエミュレーターで（Java が必要。~/.local/jdk-dl に JDK 21 を導入済み）
export JAVA_HOME=$HOME/.local/jdk-dl/jdk-21.0.12.1+1/Contents/Home PATH=$JAVA_HOME/bin:$PATH
npm run test:rules && npm run test:emu

# Web（共有ページ・OGP・規約。エミュレーター上で Chrome を使う）
cd web-tests && npx playwright test
```

## エミュレーターの起動
```
cd firebase && firebase emulators:start --only auth,firestore,storage,functions,hosting --project demo-danmaku
```
アプリをエミュレーターにつなぐ起動引数: `-use-emulator -emulator-host <MacのIP>`。

## ストアページ・規約の更新
`firebase/hosting/site.config.json`（連絡先メールなど）を直して `node firebase/hosting/build.mjs`、
`cd firebase && firebase deploy --only hosting`（Functions 未デプロイの間は `--config firebase.static.json`）。

## 公式ステージの更新
`python3 tools/make_official_stages.py` → `DanmakuCore` の `StageBot` で確認 → `python3 tools/make_official_doc.py`。
