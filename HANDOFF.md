# 引き継ぎメモ(弾幕メーカー)

次に作業する人(Claude Code・Koshin)向けの、コードを読んでもわかりにくい覚え書き。

## アプリ内課金の「参照名」
- 参照名は、App Store Connect(ASC)と RevenueCat の画面で商品を見分ける名前。審査には出ない。ASC の商品ページの「参照名」欄から後で直せる(IDは直せない)。
- 付け方: バラのパターンは `<英語名> Pattern`、全部入りは `Pattern Pack` / `Pattern Pack 2`。商品IDは `com.koshin.danmakumaker.<id>`。
- 元の表は `tools/asc_create_iaps.mjs`(ASC)と `tools/rc_create_products.mjs`(RevenueCat)。**アプリ内の名前を変えたら、この表の表示名も直し、ASC の「ローカライズ」の表示名も手で直す**(参照名も直せるが、審査には出ないので、表示名だけ合わせれば足りる)。
- 注意: 参照名は旧名のまま残るものがある。
  - `pattern.beam` … 参照名は `Beam Pattern`(旧「光線」)のまま。アプリ内の名前は「一列弾」/ Bullet Line に変え、ASC の表示名は「一列弾の弾幕」/「Bullet Line Pattern」に直した(承認済みの表示名を直すと、新しい表示名が「提出準備中」の別の行として並び、審査に通ると切り替わる。そのため `pattern.beam` も審査の下書きに入れる)。

### 弾幕パック2(2026-10-31 追加。12商品)
| 商品ID(`com.koshin.danmakumaker.` の後) | 参照名 | 価格 |
|---|---|---|
| pattern.mine | Mine Pattern | ¥300 |
| pattern.meteor | Meteor Pattern | ¥300 |
| pattern.gridLaser | Grid Laser Pattern | ¥300 |
| pattern.sweepLaser | Sweeping Laser Pattern | ¥100 |
| pattern.giantOrb | Giant Orb Pattern | ¥100 |
| pattern.bubble | Swelling Bubble Pattern | ¥100 |
| pattern.gravity | Gravity Shot Pattern | ¥100 |
| pattern.orbit | Satellites Pattern | ¥100 |
| pattern.snake | Snake Pattern | ¥100 |
| pattern.shatterRing | Shatter Ring Pattern | ¥100 |
| pattern.homingRing | Homing Ring Pattern | ¥100 |
| patternpack2 | Pattern Pack 2 | ¥600 |

- 弾幕パック1(11個)と同じ数に保つ。パック1は `patternpack`(参照名 `Pattern Pack`)。
- 既存の別系統: `patternmaker`(参照名 `Pattern Maker`、¥1,000)、`lifetime`(参照名 `Lifetime Pack`、¥3,000)。

## 1.0.5 の審査提出まで(2026-11-01 時点)
- 1.0.4(ビルド28)は「審査待ち」だったので、審査から削除し、同じバージョンページの番号を 1.0.5 に書き換えて、ビルド35を選んだ。
- Firebase(functions と firestore.rules)は反映済み。課金12商品は ASC・RevenueCat に登録済み。説明文・新機能(日英)、App プライバシー(デバイスID に「アプリの機能」を追加)も更新済み。
- 審査の下書き(アプリ1+課金15=16件)に入れてある。課金15は、弾幕パック2の12商品と、1.0.4 の取り下げで外れた `lifetime` と `patternmaker`、表示名を直した `pattern.beam`。
- 2026-11-02: 「審査へ提出」済み(16項目、ビルド35)。実機確認と UMP の巻き戻しはしないと Koshin が判断。
- 2026-11-02: APNs 認証キー(名前 `Danmaku APNs`、Key ID `A6GRJRY39Z`、Team ID `49Q2CLPBWK`、Sandbox & Production)を作り、Firebase の開発用・本番用の両方に登録済み。`.p8` は `~/.local/apns-key/` にあるだけで、リポジトリには入れない(Apple から再ダウンロードはできない)。

## 課金の登録スクリプトの注意
- `tools/asc_create_iaps.mjs` は、`/private/tmp/claude-501/iap_ids.json`(商品ID→ASC のページ番号)があると、その商品を開いて足りない設定(配信地域・価格・表示名・画像)を補う。**ファイルがないと、同じ商品IDをもう一度作ろうとして失敗する**(今回、gridLaser などが途中で止まった原因)。止まったら、一覧からIDを集めてこのファイルを作り、1商品ずつ流し直す。
- 審査用スクリーンショットは、アップロードが終わる前にページを移ると途切れる。アップロード後は30秒以上待つ。
- RevenueCat のスクリプト(`rc_create_products.mjs`)は、商品ごとにタブを開いたままにする。流し終わったらタブを閉じる(20枚を超えると Chrome が固まる)。

## ASC を Playwright で操作するときの癖(今回わかったこと)
- ビルドを外したら **「保存」を押す**。押さないと、再読み込みで元に戻る。
- ビルド欄の削除ボタンは、行にホバーすると出る(`td:last-child button`、`force: true`)。
- Mac が重いと `connectOverCDP` がタイムアウトする。専用 Chrome を閉じて開き直し、少し待つと直った。

## スワイプ弾幕(新モード、2026-11-02 時点で仕様のみ)
- ブランチ `swipe-mode-spec`。仕様書 `docs/SWIPE_MODE.md`、ブラウザ試作 `docs/swipe_prototype.html`(手ざわりと演出の正解。仕様の数値はここから写した)。
- 1.0.5 の審査は通った(2026-11-03 に Koshin が確認)ので、main に入れてよい。ASC では 1.0.6 が「配信準備完了」(公開中、2026-11-03 に画面で確認)。スワイプ弾幕は新しいバージョン(1.1.0 を提案)で出す。実装は仕様書の 13 章の分担どおり。進み具合は下の「実装の進み具合」。
- 決まったこと: 1プレイ=スタミナ1・被弾で終了、点数は上限なし(兆・億・万、英語はカンマと K〜Dc の後は指数)、ランダムの並びで序盤は易しく、サーバーが配る乱数の種でランキングを検証、ボットでクリアできると確かめたクリップだけ流す、回復ドリンク ¥120、無限スタミナパス 月額 ¥980(ランキングは割り切って対象にする、無料体験なし)。
- 出す前に必ず: 永久買い切りの説明に「消耗品と定期購読は含みません」を足す。RevenueCat を Firebase の uid で `logIn` する変更は、既存の購入の復元が壊れないか実機で確かめる。

### 実装の進み具合(スワイプ弾幕)
- 済み(`DanmakuCore`、テスト 266 件が通る): `BigScore`(上限なしの点数)、`ScoreFormat`(日本語・英語の表示)、`SwipeScoring`(点数・連続・コンボ・ボム)、かすりの判定(`Simulation`)、`SwipeClip`(早送り・安全な位置・バリア)、`SwipeClipPicker`(10 秒の区間の選び方)、`SwipeFeed`(連続に合わせた並び)、`SwipeRun`(1 プレイ分の記録から点数を計算し直す。アプリとサーバーの基準)。点数の正解は Python の整数で別に計算した値。
- 試作の不具合を直した: ボムが弾の配列を回している最中に弾を消していて、最初のボムで落ちていた。仕様 5 章に「ボムはそのステップの弾の処理が終わった後に出す。被弾したステップでは出さない」と書いた。**Claude.ai に公開してある試作のリンクは古いまま**(修正は `docs/swipe_prototype.html` にだけ入っている)。
- 次: サーバー(TypeScript): `fullsim.ts` に同じ手順(スワイプ用の作り方・かすり・`SwipeScoring`・`SwipeClip`・`SwipeFeed`・`SwipeRun`)を移し、Swift と一致するテスト(フィクスチャ)を作る → クリップの保存・候補の一覧・スタミナ・記録の検証 → アプリ(SwiftUI・SpriteKit)→ 課金の登録 → TestFlight。
- ブラウザのログイン(2026-11-03 確認): ASC・RevenueCat・Apple Developer は専用 Chrome(`open -na "Google Chrome" --args --remote-debugging-port=9222 --user-data-dir=$HOME/.local/chrome-debug`)でログイン済み。Chrome が 1 つだけのときのポートは `127.0.0.1:9222`(`[::1]` ではない)。

## スワイプ弾幕 1.1.0 の進み具合（2026-11-03 夜）

完了:
- DanmakuCore（SwipeClipPlayer まで）、サーバー TS の移植（fullsim.ts の createSim / swipe.ts / swipebot.ts / stamina.ts / swipefns.ts）、Swift↔TS の一致テスト（CI の Xcode 26 でも一致）、エミュレーター通しテスト、ルールのテスト
- アプリ: Swipe/ 一式（SwipeHomeView / SwipeModel / SwipeScene / SwipeAudio / SwipeService / SwipeConfig）、10 言語の文言、本編の「もう一度」は広告なし・全画面広告は 2 プレイごと（やめるとき）・クリア後に広告でごほうび・スワイプは 15 本ごとに全画面広告
- TestFlight: 1.1.0 (37) が ASC に届いた。TestFlight・審査ビルドは swipe_enabled に関わらずスワイプ弾幕が出る（SwipeConfig.isSandbox）
- ASC: 回復ドリンク（消耗型 com.koshin.danmakumaker.stamina.drink、ID 6830164751、価格は ¥100 にした。¥120 は「他の価格を確認」から選べる）、Stamina Pass グループ（22541161）と月額 無限スタミナパス（com.koshin.danmakumaker.pass.stamina.monthly、ID 6830171590、¥980）。日本語・英語の表示名入力済み。永久買い切りの説明文を更新（消耗品と定期購読は除く）
- RevenueCat: 商品 2 つを追加、Webhook（購入通知）を追加（合言葉は /tmp/rc_secret と Firebase の REVENUECAT_WEBHOOK_SECRET に同じ値）

残り:
1. 本番デプロイ（Koshin が `firebase deploy --only firestore:rules,functions,remoteconfig --project danmaku-maker`）。済んだら Cloud Scheduler で swipeCheckMissingClips → swipeBuildPool を「強制実行」して候補を作る
2. ASC: 2 つの課金の審査用スクリーンショット（CI の UI Screenshots の成果物 swipe_stamina を使う）、1.1.0 のバージョン作成・説明文（スワイプ弾幕と課金の記載、EULA リンク）・ビルド 37 以降を選択・課金 2 つとドリンクを提出物に追加
3. 実機確認（TestFlight、Koshin）: 遊べる・音・触感・購入（サンドボックス）・RevenueCat の logIn 後の購入復元
4. 「審査へ提出」は Koshin

---

## 2026-11-09 の作業メモ(swipe-mode-spec)

アプリ 1.1.3 の内容と、**サーバーのデプロイ待ちの項目**。

### 入れたもの
- 世界のステージ: 動くミニプレビュー・流れるタイトル・見せ場の開始秒・プレビューなし(ネタバレ防止)・長押しで大きく再生
- 称号: スコア達成4段階、月間ランキング(毎月1日 0:00 JST で区切り)の順位報酬(王冠・メダル・上位%)。称号は永久。王冠・名前の色は次の月まで
- エディタ: 弾の形(標準/くの字/丸)、発射間隔 15 秒まで、ボスの動き 7 種類(上下・円・8の字・ワープを追加)
- 世界のステージ: 作者で絞り込み
- 設計書: `docs/ADS_PROPOSAL.md`(フェーズ4)、`docs/FRIEND_INVITE_DESIGN.md`(フェーズ3)、`docs/BOSS_ROSTER_PLAN.md`(ボス6体の移植計画)

### デプロイ(本番)が必要なもの — 1.1.3 の TestFlight で確認する前に
フェーズ1の関数(開始秒・プレビューなし)は、デプロイ済み。それ以降の、次の3つが未デプロイです。
1. `firebase deploy --only functions`(`FUNCTIONS_DISCOVERY_TIMEOUT=120` を付ける): 称号・月間ランキング(`swipeMonthlyAward`、毎月1日 0:05 JST)・`setTitle`・発射間隔/弾の形/ボスの動きの検証
2. `firebase deploy --only firestore:rules`: `titleState` / `publicProfiles`
3. `firebase deploy --only firestore:indexes`: 作者での絞り込み用の索引(作成に数分かかる)
- 先にサーバーを出さないと、新しいアプリの「今月」ランキング・称号・作者での絞り込みは動きません(古いサーバーの応答は、アプリ側で月間として見せないようにしてあります)。
- 発射間隔が 2 秒を超えるステージ・新しいボスの動きは、**古いアプリ(1.1.2 以前)では、間隔 2 秒・横の動きに丸められて遊ばれる**ため、クリア記録の検証がずれることがあります。

### テスト(すべて通過)
`cd DanmakuCore && swift test` / `cd firebase/functions && npm run lint && npm test && npm run test:rules && npm run test:emu`(JDK の環境変数と、先に `npm run build` が要る)
