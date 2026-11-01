# 引き継ぎメモ(弾幕メーカー)

次に作業する人(Claude Code・Koshin)向けの、コードを読んでもわかりにくい覚え書き。

## アプリ内課金の「参照名」
- 参照名は、App Store Connect(ASC)と RevenueCat の画面で商品を見分ける名前。審査には出ない。ASC の商品ページの「参照名」欄から後で直せる(IDは直せない)。
- 付け方: バラのパターンは `<英語名> Pattern`、全部入りは `Pattern Pack` / `Pattern Pack 2`。商品IDは `com.koshin.danmakumaker.<id>`。
- 元の表は `tools/asc_create_iaps.mjs`(ASC)と `tools/rc_create_products.mjs`(RevenueCat)。**アプリ内の名前を変えたら、この表の表示名も直し、ASC の「ローカライズ」の表示名も手で直す**(参照名は直せないので、表示名だけ合わせる)。
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
- Firebase(functions と firestore.rules)は反映済み。
- 残り: 課金12商品の登録(ASC・RevenueCat)、APNs キー、UMP の扱いの確認、説明文・新機能の更新、App プライバシーの確認、実機確認、審査へ提出(Koshin)。

## 課金の登録スクリプトの注意
- `tools/asc_create_iaps.mjs` は、`/private/tmp/claude-501/iap_ids.json`(商品ID→ASC のページ番号)があると、その商品を開いて足りない設定(配信地域・価格・表示名・画像)を補う。**ファイルがないと、同じ商品IDをもう一度作ろうとして失敗する**(今回、gridLaser などが途中で止まった原因)。止まったら、一覧からIDを集めてこのファイルを作り、1商品ずつ流し直す。
- 審査用スクリーンショットは、アップロードが終わる前にページを移ると途切れる。アップロード後は30秒以上待つ。
- RevenueCat のスクリプト(`rc_create_products.mjs`)は、商品ごとにタブを開いたままにする。流し終わったらタブを閉じる(20枚を超えると Chrome が固まる)。

## ASC を Playwright で操作するときの癖(今回わかったこと)
- ビルドを外したら **「保存」を押す**。押さないと、再読み込みで元に戻る。
- ビルド欄の削除ボタンは、行にホバーすると出る(`td:last-child button`、`force: true`)。
- Mac が重いと `connectOverCDP` がタイムアウトする。専用 Chrome を閉じて開き直し、少し待つと直った。
