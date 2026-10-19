# 審査提出チェックリスト

## 審査で落ちやすい点の自己チェック
| 項目 | 状態 | 内容 |
|---|---|---|
| UGC: 通報 | ✅ | ステージ詳細の「通報する」（理由3種）。5件で自動的に非公開＋アラート |
| UGC: ブロック | ✅ | 「作者をブロック」。一覧から非表示。設定で解除 |
| UGC: NG ワード | ✅ | サーバー（publishStage）で日英の NG ワードを検査 |
| UGC: 規約同意 | ✅ | 投稿前に同意画面（規約・プライバシーへのリンク） |
| UGC: 連絡先 | ⚠️ | 設定画面とサポートページに掲載。**メールアドレスが仮（koshinstudio88@gmail.com）→ 要差し替え** |
| 広告がゲーム操作の邪魔をしない | ✅ | リワード広告は被弾後の復活のみ（ユーザー操作）。開始時の広告なし |
| 購入の復元 | ✅ | 設定画面と購入画面にボタン |
| ログインなしで遊べる | ✅ | 匿名認証。投稿・いいね・通報だけ Sign in with Apple |
| アカウント削除 | ✅ | 設定→アカウントを削除（Apple トークン失効＋サーバーでデータ削除） |
| ATT / UMP | ✅ | 広告前に同意 → トラッキング許可。NSUserTrackingUsageDescription は日英 |
| プライバシー | ✅ | 規約・ポリシー公開。App のプライバシー回答済み |
| 輸出コンプライアンス | ✅ | ITSAppUsesNonExemptEncryption=false |
| 中国本土を除外 | ✅ | 配信地域は 174（中国本土のみ除外） |

## 提出前に Koshin がやること
`docs/SUBMISSION_CHECKLIST.md` 末尾の「朝のやることリスト」、または会話の最終報告を参照。

---

# 朝のやることリスト（Koshin にしかできない作業）

優先順に並べています。先に 1〜3 をやれば、アプリのビルドと TestFlight まで進みます。

## 1. Apple Developer Program の使用許諾契約に同意（2026-10-29 期限）
1. Chrome で https://developer.apple.com/account を開く（ログイン済みの専用 Chrome でなくても可）。
2. 上部の「契約」→「契約を確認」で内容を読み、同意する。Account Holder のアカウントで行う。
3. https://appstoreconnect.apple.com/business で「有料App契約」と銀行口座・税金情報が「有効」か確認する（広告削除の買い切りを売るのに必要）。

## 2. Firebase を Blaze プランに切り替え（カード入力）
Cloud Functions / Storage を使うのに必須。無料枠内なら請求は基本 0 円です。
1. https://console.firebase.google.com/project/danmaku-maker/usage/details を開く → 「アップグレード」→ Blaze を選ぶ → カード情報を入力。
2. 同じ画面の「予算とアラート」で月 1,000 円の予算アラートを作る（Google Cloud の「お支払い」→「予算とアラート」でも可）。
3. 終わったら教えてください。Functions・Storage・Hosting のデプロイと、OGP 画像・共有ページの動作確認は私がやります。

## 3. Sign in with Apple の鍵を作って Firebase に登録（秘密鍵の入力は私にはできません）
1. https://developer.apple.com/account/resources/authkeys/add を開く → 名前 `DanmakuMaker SIWA` → 「Sign in with Apple」にチェック → Configure で Primary App ID に `Danmaku Maker (com.koshin.danmakumaker)` を選ぶ → 登録 → `.p8` をダウンロード（**一度しかダウンロードできません**。Key ID も控える）。
2. Firebase コンソール → Authentication → ログイン方法 → Apple を有効化 → 「OAuth コードフローの構成」に、Team ID `49Q2CLPBWK`、Key ID、`.p8` の中身を貼る。保存。
3. `.p8` は `.gitignore` 済みの場所（例: `~/Documents`）に保管し、リポジトリには入れない。

## 4. アプリ内課金キー（.p8）を RevenueCat に登録
1. App Store Connect → ユーザとアクセス → 統合 → アプリ内課金 → キーを生成 → `.p8` をダウンロード（一度しか不可）。
2. https://app.revenuecat.com/projects/c60cfbbd/apps で「New app configuration」→ App Store → バンドル ID `com.koshin.danmakumaker` → 「In-app purchase key configuration」にその `.p8` をアップロード → Save。
3. RevenueCat の Product catalog で、商品 `com.koshin.danmakumaker.removeads` を追加し、Entitlement `no_ads` に紐付け、Offering `default` に Lifetime パッケージとして入れる。
4. 「API keys」の `appl_…` キーを教えてください（公開キーです）。`project.yml` の `REVENUECAT_API_KEY` に私が設定します。

## 5. App Review の連絡先を入力
App Store Connect → 弾幕メーカー → iOS 1.0 → 「App Review に関する情報」に、名前・電話番号（+81…形式）・メールを入力して保存。
同じ画面の「サインインが必要」のチェックは **外す**（ログインなしで遊べます）。

## 6. サポート用メールアドレスを決める
`firebase/hosting/site.config.json` の `supportEmail`（今は仮の `koshinstudio88@gmail.com`）を決めて教えてください。ページを作り直して公開します。アプリ内の設定画面（`DanmakuApp/Services/AppConfig.swift`）も同時に直します。

## 7. ビルドを作って TestFlight へ（どちらか）
### A. Xcode Cloud（おすすめ。トレカダッシュと同じ方法）
1. Mac で `~/Desktop/danmaku/DanmakuMaker.xcodeproj` を Xcode で開く。
2. メニュー Product → Xcode Cloud → Create Workflow → ソースに GitHub の `murakamikoshin/danmaku-maker` を選び、GitHub への接続を許可する。
3. ワークフローの Environment で Xcode の最新版（26 系）を選び、環境変数 `GOOGLE_SERVICE_INFO_PLIST_BASE64` を **Secret** で追加する。値は、ターミナルで次を実行してコピーできる:
   `base64 -i ~/Desktop/danmaku/DanmakuApp/GoogleService-Info.plist | pbcopy`
4. Actions は「Archive - iOS」、Post-Actions に TestFlight（内部テスト）を追加 → 保存して Start Build。
   `ci_scripts/ci_post_clone.sh` が XcodeGen の実行と plist の復元をします。
### B. GitHub Actions（`.github/workflows/testflight.yml`。未検証）
Secrets に `ASC_KEY_ID` `ASC_ISSUER_ID` `ASC_KEY_P8_BASE64` `GOOGLE_SERVICE_INFO_PLIST_BASE64` を登録して、Actions タブから手動実行。

## 8. TestFlight で実機確認 → 審査へ提出
1. TestFlight アプリで入れて、遊ぶ → 作る → 投稿 → いいね → 通報 → 広告（テスト広告ではなく本番広告 ID なので、広告が出ない場合は AdMob の審査待ちのことがあります）→ 課金（Sandbox）を確認。
2. `docs/OFFICIAL_STAGES.md` の公式ステージ 30 本を遊んで、難易度の並びを確認。
3. ビルドが処理されたら、App Store Connect の iOS 1.0 に「ビルド」を選ぶ。
4. 私が整えておいた内容（`docs/APPSTORE_METADATA.md`）を確認し、**「審査へ提出」を押す**。

## 補足（提出画面での注意）
- **アプリ内課金**: 最初の課金アイテムは、アプリ本体と一緒に審査へ出す必要があります。iOS 1.0 のページ下部「アプリ内課金とサブスクリプション」で `Remove Ads` を選んでから「審査用に追加」を押してください（IAP の価格・日英の表示名・審査用スクリーンショットは入力済み）。
- **韓国**: ゲームは、韓国のゲーム物管理委員会(GRAC)の分類番号が無いと韓国のストアに出ません。韓国で配信しないなら、価格および配信状況から韓国も外してください（中国本土は除外済み）。
- **ストア画像**: 日英とも 1290×2796（6.9 インチ）の5枚を入力済みです。必須の 6.1 インチ枠には自動で縮小されて入ります。画像の元データは `docs/store_screenshots/`。
- **広告の本番 ID**: Release ビルドは本番の AdMob ID を使います。新しいアプリは AdMob 側の審査が済むまで広告が出ない（または少ない）ことがあります。TestFlight では広告が出なくても異常ではありません。
- **AdMob SDK**: この Mac（Xcode 15.2）でビルドできる最新の 11.2.0 を使っています。Xcode Cloud で Xcode 26 が使えるので、提出後に最新版（13.x）への更新を検討してください（Swift の API 名が変わるため、コードの書き換えが必要です）。

---

## 追加: 見た目パック・撃ち方の課金商品(2026-10-19)

広告削除(¥600)に加えて、買い切りの商品を14個追加した。すべて「非消耗型」。

| 種類 | 商品ID | 価格 |
|---|---|---|
| 弾の色と形 / 背景 / 自機(桜・深海・オーロラ × 3) | `com.koshin.danmakumaker.<theme>.<bullets/background/ship>` | ¥100 |
| テーマのセット(3点) | `com.koshin.danmakumaker.<theme>.set` | ¥200 |
| 撃ち方(ワイド・ヘビー) | `com.koshin.danmakumaker.shot.<spread/heavy>` | ¥300 |

- 価格は App Store Connect の日本の価格表(¥100 刻み)に合わせた。¥120 や ¥250 は選べない。
- 撃ち方は1秒あたりの威力が同じ(約22)。投稿前のテストプレイは、必ず標準の撃ち方で行う。
- アプリ側の購入判定は RevenueCat の `allPurchasedProductIdentifiers` を使う。RevenueCat 側でエンタイトルメントを作る必要はない(広告削除の `no_ads` だけは作る)。
- 審査に出すとき、バージョンページの「アプリ内購入」で、広告削除と14商品のすべてを選ぶ。
- 商品登録の自動化スクリプト: `tools/asc_create_iaps.mjs`

## 追加: RevenueCat の設定(2026-10-19 完了)
- アプリ「弾幕メーカー (App Store)」を作成し、アプリ内購入キー(Key ID `VSUPUV2MUC`)を登録済み。
- 商品15個(広告削除 + 14商品)を登録済み(`tools/rc_create_products.mjs`)。
- 権利 `no_ads` に `com.koshin.danmakumaker.removeads` を結びつけ済み。
- オファリング `default` に、Lifetime パッケージ(広告削除)を作成済み。
- アプリの公開キーは `project.yml` の `REVENUECAT_API_KEY` に設定済み(公開キーなのでコミットしてよい)。

## 追加: 提出直前の状態(2026-10-19 夜)
- アプリ内購入は16個(広告削除 ¥600、パーツ12個 ¥100〜¥200、撃ち方2個 ¥300、じぶんの画像 ¥500)。すべて App Store Connect と RevenueCat に登録済み。
- アプリアイコンを設定済み(`tools/make_app_icon.py` で、ゲームの実際の部品から生成)。
- ビルド 1.0.0 (4) を GitHub Actions(`.github/workflows/testflight.yml`)で作って TestFlight に配信済み。内部テスト「内部テスト」グループに Koshin(koushin0224@icloud.com)を追加済み。
- App Store Connect の「提出物の下書き」には、iOS 1.0.0 (4) とアプリ内購入16個、合計17件が入っている。
- コンテンツ配信権は「はい(必要な権利を保有)」にした(他のユーザーが投稿したステージを表示するため)。
- **最後の「審査へ提出」は、Koshin が実機確認のあとに押す。** 場所: App Store Connect →「弾幕メーカー」→「配信」→「iOSアプリ 1.0」→ 右下の「提出物の下書き」→「審査へ提出」。
- ビルドを作り直すとき: `gh workflow run TestFlight --ref main`(Secrets は GitHub に登録済み)。新しいビルドができたら、バージョンページの「ビルド」で選び直す。
- 紹介画像(スクリーンショット)は、日英とも5枚(ゲーム画面)。ショップ画面の画像は `docs/store_screenshots/` にあるが、App Store には未登録(任意)。

## 追加: 機能拡張後の状態(2026-10-19 深夜)
- アプリ内購入は28個: 広告削除、見た目12、撃ち方2、じぶんの画像、追尾弾、弾幕10種(花・星・ハート・光線・十字・加速・反射・ストップ&ゴー・分裂・時差)、弾幕パック。すべて ASC と RevenueCat に登録済み。
- 弾幕パックの価格は ¥600 のまま(含まれる弾幕は11種に増えた)。
- マイステージ(保存と投稿を分離)、連戦(場面1〜6)、警告音、撃破演出、予告のオンオフ、かんたん/くわしく、ステージごとの見た目、世界ランキング、コメントを実装。
- サーバー(Functions・ルール・インデックス・Hosting)は本番に反映済み。
- 審査用メモには「ログインなしで遊べる」「コメントは通報・ブロック・NG ワード・3件の通報で自動非表示」「ランキングはサーバーで操作記録を再生して検証」を書く。
- 最後の「審査へ提出」は Koshin。その前に実機(TestFlight)で、購入・広告・連戦・演出を確認する。
