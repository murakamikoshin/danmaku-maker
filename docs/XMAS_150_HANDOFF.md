# 1.5.0 クリスマス 引き継ぎメモ(2026-11-25)

ブランチ `xmas-150`(`requests-142` から分岐)。中身の一覧は `docs/SEASONAL_BOSS.md`。ここは「いまの状態」と「残りの作業」だけ。

## 守ること(Koshin の決まり)
- テストは必ず回す。
- ビルドは、Koshin が「作って」と言うまで作らない。
- push・本番デプロイ・審査提出の前は、止まって確認する(`xmas-150` への作業中の push だけは許可済み)。

## いまの状態
- **テストは通っている**: `DanmakuCore` の `swift test` 470 件、`firebase/functions` の unit / ownership / appversion 251 件、Swift とサーバーの計算一致(fullsim)4516 件。
- **アプリの画面のコード(`DanmakuApp/`)は、一度もコンパイルしていない。** Linux の作業場で書いたので、最初のビルドでエラーが出る見込み。今回さわった主なファイル:
  `ShopView.swift`(SeasonPackCard / MookShopCard / PaidShipSection)、`HomeView.swift`(SeasonPromoBanner / SeasonBannerBackdrop)、`Editor/EditorView.swift`、`Editor/PublishFlowView.swift`、
  `Game/BossSprites.swift`、`Game/GameScene.swift`、`Game/EnemyArt.swift`、`Game/ShipSkin.swift`、`Game/Skin.swift`、`Game/BulletArtData.swift`、`Services/SeasonConfig.swift`、`Services/CosmeticsStore.swift`、`Services/AudioManager.swift`、`SettingsView.swift`、`InviteView.swift`
- 文言は `tools/add_xmas_strings.py` で 10 言語ぶん入れてある(足すときはこの中の表に足して、もう一度走らせる)。

## 残りの作業(順番)
1. **ビルドして、コンパイルエラーを直す**(Koshin が「作って」と言ってから)。
2. **App Store Connect と RevenueCat に、商品 10 個を登録**(Koshin の手作業。ID と値段は `docs/SEASONAL_BOSS.md` の表)。
3. **TestFlight で実機確認**(サンドボックスと TestFlight は、期間に関係なく売り場に出る)。見るところ:
   - ホームの赤いお知らせ(見出しが折れていないか、長い言語で縮みすぎていないか)→ 押すとショップのクリスマスパックへ飛ぶか
   - ショップ: パック・ノエル・雑魚セット・自機 3 種・テーマ。買う / 復元 / 買ったあと「持っている」になるか
   - ノエル: 待機 16 コマがなめらかに動くか、技中・覚醒(黒サンタ)、専用の弾 4 種の絵
   - エディタ: 雑魚の見た目 5〜8(お試しの印)、テーマ「クリスマス」、BGM「クリスマス」、持っていないと公開で止まるか
   - 公式ステージ o38「ノエルのクリスマス」(サンプルのいちばん最後)
   - 設定「当たり判定の点を表示」(最初はオフ)
4. **サーバー(Functions)と Remote Config を本番に反映**(止まって確認)。Remote Config のひな形は、本番の最新と見比べてから(ひな形の版が古いかもしれない)。
5. **審査に出す**(止まって確認)。目標は 12/9〜12/10。1.4.2 が先に通ったら、`requests-142` の変更を取り込んでから。
6. 期間が終わったら(12/26 17:00 のあと)、ASC で商品を「販売から削除」(手順は `docs/SEASONAL_BOSS.md`)。

## 分かっている弱いところ(正直なメモ)
- BGM(`bgm_xmas.caf`、`tools/make_xmas_bgm.py`)は、数値で確かめただけで、耳では聴いていない。
- ノエルの技は、初期値だとかなり簡単(自動プレイのボットが被弾なしで倒せる)。公式ステージは弾数と速さを上げてある。技そのものを強くするなら、`SantaPatterns.swift` と `firebase/functions/src/santa.ts` の両方と、計算一致の見本(santa の分だけ)を作り直す。
- 雑魚の絵・自機の絵は 1 回目の出来。元絵と作るスクリプトは `swipe-mode-spec` ブランチの `art/mooks/xmas`・`art/ships/xmas`・`art/bosses/santa`。
- 試射場(`swipe-mode-spec` の `art/bosses/patterns`)のノエルの見本は、ゲームの実装と少し違う(箱の飛び方、ツリーの覚醒)。
- ASC で「販売から削除」したあとの復元は、サンドボックスで確かめていない。
- 技の列挙(`Pattern`)は、**新しい技を必ず最後に足す**(途中に入れると、ほかのステージの乱数の種が変わる。`SantaPatternTests` に見張りのテストがある)。
- 計算一致の見本(`sim_fixtures.json`)は、Linux で作り直すと Mac と違う値になる。作り直さず、新しい分だけ足す。
