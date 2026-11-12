---
name: danmaku-boss
description: 弾幕メーカーの新しいボス(ドット絵・待機/技/覚醒アニメ・限定弾幕5つ)を、決まった作り方で作る・作り直すときに使う。「ボス作って」「/danmaku-boss」など
---

# 弾幕メーカーのボスを作る

Koshin のゲーム『弾幕メーカー』のボスを、決まった作り方で作る。会話は日本語・くだけた口調で、正直に。

## 0. 準備
- ブランチは **swipe-mode-spec だけ**(main は古い。main に置くと Koshin が見つけられない)。始める前に最新を取り込む
- 最初に `art/bosses/_pipeline/README.md` と `art/bosses/CLAUDE.md` を全部読む。**細かい手順・設定の書き方は README が正**。ここはその要約
- 見本: `art/bosses/kitsune/`(ふつうのドット化)、`fallen_angel/` `ice/` `reaper/`(色の表を使うドット化)、`hire/`(金魚姫)
- ぷにまるは作り直さない

## 1. テーマを決める
- Koshin にボスのテーマ(名前・見た目・持ち物・技の雰囲気)を聞く。決まっていれば聞かずに進める
- **オリジナルのキャラだけ**。既存作品のキャラに似た組み合わせにしない

## 2. 元絵(AI の画像生成)
README のひな形で頼む: 3.5頭身、かわいすぎない不敵な笑み・少しつり目、宙に浮いて片足を曲げたポーズ・ほぼ正面、濃い輪郭線、1段のベタ影、グラデーションなし、色数少なめ、全身、背景は真っ白。
- 画像を作る道具(Canva など)が使えないときは、Koshin に ChatGPT / Gemini などで作って渡してもらう(頼む文はこちらで書く)
- 6頭身以上で返ってきたら頼み直す(顔がつぶれる)
- 保存先: `art/bosses/<ID>/source/<ID>_source.png`(export が1コマ目の画像を消すので、元絵は必ず source/ に)

## 3. ドット化
`python3 art/bosses/_pipeline/make_still.py art/bosses/<ID>`
- 決まりごと: 黒い枠なし、灰色なし、素材ごとに色は3段(肌と白は2段)、目は1色の縦長 2×3
- 黒が多い・白が多い・細い金の線がある絵は、`source/<ID>_settings.json` に `palette` を書いて色の表を使うドット化にする(書き方は README の 2-b)
- 顔がつぶれたら `source/<ID>_face.json` で顔と目を描き直す
- 暗い背景に拡大して必ず目で見る。色が濁る・点が散る・顔が消えるなら直してから次へ

## 4. 部位の地図
`source/<ID>_parts.json` に元絵の座標で多角形を書く。種類は body / flow / ribbon / held / floating(README の表)。
- 手・持ち物・脚は動かさない。部位の形に手を入れない(ちぎれて見える)
- floating は「まわりに何もない所に浮いている物」だけ。体に重なる物は ribbon
- `_partmap_view.png` を見て、部位が合っているか確かめる

## 5. アニメと技
- `art/bosses/<ID>/make_<ID>.py`(見本をまねる): 待機8・構え4・技中4・硬直2、覚醒も同じ4つ
- 限定弾幕パターン5つと専用の弾(色も特殊に)を `art/bosses/patterns/engine.js` と `spec.py` に。発射位置は `art/bosses/tools/srcpos.py` の `to_frame` で元絵の座標から出す
- `art/bosses/tools/build_viewer.py` のボス一覧に足す

## 6. プッシュ前の確認(毎回)
- 待機8コマを暗い背景に並べて拡大して見る。GIF も作って Koshin に見せる
- 透明な切れ込み(上下か左右を色にはさまれた透明なドット)を数え、元の絵より増えていないか
- 手・持ち物・脚が動いていないか、浮いた物の下に影が残っていないか

## 7. 仕上げ
- `cd art/bosses/patterns && python3 build.py <出力>/boss_patterns.html && python3 ../tools/build_viewer.py <出力>/boss_zukan.html` で試射場・ボス図鑑を作り直す
- swipe-mode-spec にコミットしてプッシュ
- アプリ本体(DanmakuApp/Resources/Bosses)への組み込みは別作業。やるかどうかは Koshin に聞く
- 報告は短く: できたもの、気になる点(正直に)、次にやれること
