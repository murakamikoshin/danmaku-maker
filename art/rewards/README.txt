自機スプライト（弾幕メーカー用）
- 全部 32x32 / 透過PNG / 機首が上向き
- フォルダ = 機種_カラー、中のファイル = 機種_カラー_コマ番号.png
- 通常機: 3コマ（0→1→2→1 でループ。噴射炎アニメ）
- seraph_special: 4コマ（0→1→2→3 でループ。翼の色・オーラ・きらめきが動く）
- 拡大表示時は filteringMode = .nearest

ticket_rainbow（レアチケット）
- 64x28 / 透過PNG / 8コマ（0→7 でループ。虹色が流れ、0〜3コマ目で光の帯が横切る）
- 拡大表示時は filteringMode = .nearest

drink_rainbow（虹色の回復ドリンク）
- 32x32 / 透過PNG / 1枚（アニメなし）。文字なし・黒い縁取りなし
- 丸いフラスコに虹の6色の液、金のふた
- 作り直しは _tools/make_drink_rainbow.py
- 拡大表示時は filteringMode = .nearest
