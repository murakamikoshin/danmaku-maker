# 竜王のBGM(流し方・使い方)

竜王戦専用のオリジナル曲。ニ短調・BPM176。メロディもコードも自作で、`make_bgm.py` が一から合成する(素材は使っていない)。
**ゲーム本体(DanmakuApp)には、まだ入れていない。** 入れるときの手順は下。

## ファイル

| ファイル | 長さ | 使い道 |
|---|---|---|
| `bgm_ryuou_intro.caf` | 5.46秒 | ゲーム用。竜王戦の始まりに **1回だけ** 流す |
| `bgm_ryuou_loop.caf` | 54.55秒 | ゲーム用。イントロのあと **ずっと繰り返す** |
| `ryuou_full.mp3` | 約2分 | 試聴用(イントロ → 本編2周 → 締め)。ゲームには入れない |
| `make_bgm.py` | - | 曲を作るスクリプト。元の WAV(44.1kHz ステレオ)はこれで作り直せる |

### 2曲目「怖さ・ラスボス感」(2026-11-17 追加)

ニ短調・BPM144。鐘・パイプオルガン・合唱が軸で、明るい響きを避けた不穏な進行(Dm→B♭m、減和音)。1曲目より遅くて重い。

| ファイル | 長さ | 使い道 |
|---|---|---|
| `bgm_ryuou2_intro.caf` | 6.67秒 | ゲーム用。**1回だけ** 流す(鐘と心臓の鼓動 → 合唱とオルガン → ティンパニのロール) |
| `bgm_ryuou2_loop.caf` | 53.33秒 | ゲーム用。イントロのあと **ずっと繰り返す** |
| `ryuou2_full.mp3` | 約2分 | 試聴用。ゲームには入れない |
| `make_bgm2.py` | - | 2曲目を作るスクリプト(使い方は `make_bgm.py` と同じ。出るのは `ryuou2_*.wav`) |

流し方・本体への入れ方は1曲目と同じで、下の説明の `bgm_ryuou_…` を `bgm_ryuou2_…` に読み替える(`Track` に足すなら `case ryuou2 = "bgm_ryuou2_loop"`。`playRyuou()` はファイル名を引数にすれば両方に使える)。

**2曲の使い分けは、まだ決まっていない。** 案: 通常は1曲目・覚醒したら2曲目に切り替える / どちらか1曲だけ使う。切り替えるなら、2曲目はイントロから入ると場面が変わった感じが出る。決めるのは Koshin。

caf は、本体の他の BGM と同じ形式(IMA4・22050Hz・モノラル)。

## 流し方

1. 竜王戦が始まったら `bgm_ryuou_intro` を1回流す
2. イントロが終わる瞬間に `bgm_ryuou_loop` を始めて、戦闘が終わるまで繰り返す
3. 戦闘が終わったら、今の BGM と同じようにフェードアウト

- イントロとループは、同じ音量でそのままつながる(間を空けない・重ねない・フェードしない)
- ループの終わりと頭は、残響ごとつながるように作ってある。繰り返すだけで切れ目は出ない
- イントロの切り替えが面倒なら、**ループだけ繰り返しても成立する**(今の `AudioManager.play` に曲を1つ足すだけで済む)
- 再挑戦のときは、イントロを飛ばしてループから始めてもいい

## 本体に入れるとき

1. caf 2つを `DanmakuApp/Resources/Audio/` にコピー
2. `AudioManager.Track` に `case ryuou = "bgm_ryuou_loop"` を足す
3. ループだけでいいなら、竜王戦で `AudioManager.shared.play(.ryuou)` を呼ぶ。これで終わり
4. イントロも付けるなら、`AudioManager` に下を足して `playRyuou()` を呼ぶ

```swift
private var introPlayer: AVAudioPlayer?

/// 竜王戦: イントロを1回 → 切れ目なくループへ
func playRyuou() {
    guard current != .ryuou || player?.isPlaying != true else { return }
    current = .ryuou
    guard bgmOn,
          let iu = url("bgm_ryuou_intro"), let lu = url("bgm_ryuou_loop"),
          let intro = try? AVAudioPlayer(contentsOf: iu),
          let loop = try? AVAudioPlayer(contentsOf: lu) else { return }
    let old = player
    old?.setVolume(0, fadeDuration: 0.3)
    if let old { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { old.stop() } }

    intro.volume = bgmVolume; loop.volume = bgmVolume
    loop.numberOfLoops = -1
    intro.prepareToPlay(); loop.prepareToPlay()
    // 同じ時計で予約するので、イントロの終わりとループの頭がずれない
    let start = intro.deviceCurrentTime + 0.1
    intro.play(atTime: start)
    loop.play(atTime: start + intro.duration)
    introPlayer = intro
    player = loop   // 止める・フェードは今までどおり player に効く
}
```

注意:
- `fadeOut()` と `pause()` に `introPlayer?.stop()` / `introPlayer?.pause()` も足す(イントロ中に止めたとき、イントロだけ鳴り続けないように)
- イントロ中にアプリが裏に回ると、予約したループの開始がずれる。戻ったときは `playRyuou()` を呼び直すか、ループだけ鳴らす
- BGM オフから戻す `resume()` は `play(c)` を呼ぶので、竜王のときはループから始まる(イントロなし)。それで問題ない

## 曲の中身

- イントロ(4小節): ティンパニと低い弦 → ブラスのファンファーレ、スネアロール
- A(8小節×2): ギャロップ刻みのギターに主題。2周目はツインリードでハモる
- B(8小節): ハーフテンポで重く落として、タム回しで溜める
- サビ(8小節×2): 高音のリードにブラスを重ねる。2周目はツーバス連打

## 作り直すとき

```
python3 make_bgm.py <出力フォルダ>      # numpy と scipy が要る。ryuou_intro.wav / ryuou_loop.wav / ryuou_full.wav が出る
ffmpeg -i ryuou_loop.wav  -ac 1 -ar 22050 -c:a adpcm_ima_qt bgm_ryuou_loop.caf
ffmpeg -i ryuou_intro.wav -ac 1 -ar 22050 -c:a adpcm_ima_qt bgm_ryuou_intro.caf
ffmpeg -i ryuou_full.wav -b:a 192k ryuou_full.mp3
```

速さは `BPM`、メロディは `MEL_A` / `MEL_B` / `MEL_C`(音の高さ, 16分音符いくつ分)、コードは `SEC`、音量のバランスは `build` の最後の `norm(…)` の数字。

## 分かっていること

- 作った Claude は音を聴けない。音割れなし・ループのつなぎ目に段差なし、までは数値で確かめた。かっこいいかは Koshin の耳で決める
- 全部シンセ合成なので、生のギターやオーケストラの質感ではない
- 覚醒の段階ごとに曲が変わる作りにはしていない(2曲あるだけ)
- 2曲目の合唱と鐘はシンセで作った「それっぽい音」で、本物の声や鐘ではない
- caf はモノラル・22050Hz に落としているので、`ryuou_full.mp3` より少しこもって聴こえる
