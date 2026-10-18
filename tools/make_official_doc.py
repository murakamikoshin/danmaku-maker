#!/usr/bin/env python3
"""公式ステージの確認用一覧(docs/OFFICIAL_STAGES.md)を作る。入力: official_stages.json と、StageBot の出力(docs/official_stages_bot.txt)"""
import json, pathlib, re
root = pathlib.Path(__file__).resolve().parent.parent
stages = json.loads((root / "DanmakuApp/Resources/official_stages.json").read_text())
bot = {}
for line in (root / "docs/official_stages_bot.txt").read_text().splitlines():
    m = re.match(r"(o\d\d)\s+\d\s+(boss|survive)\s+\d+\s+(\w+)\s+([\d.]+)s(?:\s+hp(\d+))?\s+(\w+)\s+([\d.]+)s(?:\s+hp(\d+))?", line)
    if m: bot[m[1]] = m
LABEL = {1: "★ 入門", 2: "★★ やさしい", 3: "★★★ ふつう", 4: "★★★★ むずかしい", 5: "★★★★★ 激ムズ"}
def bot_text(i, boss):
    m = bot.get(i)
    if not m: return "—"
    def one(res, sec, hp):
        if boss: return {"CLEAR": f"撃破 {sec}s", "TIME": f"時間切れ(残HP {hp})", "HIT": f"被弾 {sec}s(残HP {hp})"}[res]
        return {"CLEAR": "クリア", "HIT": f"被弾 {sec}s"}.get(res, res)
    return f"弱:{one(m[3], m[4], m[5])} / 強:{one(m[6], m[7], m[8])}"
rows = []
for s in stages:
    st = s["stage"]; boss = st["mode"] == "boss"
    spec = f"ボス HP{st['bossHp']}・{st['durationSec']}秒" if boss else f"耐久 {st['durationSec']}秒"
    rows.append(f"| {s['id']} | {LABEL[s['difficulty']]} | {s['name']['ja']}<br><sub>{s['name']['en']}</sub> | {spec} | {s['aim']['ja']} | {bot_text(s['id'], boss)} | ☐ |")
doc = f"""# 公式サンプルステージ 確認用一覧

全 {len(stages)} 本。アプリの「サンプル」タブに、易しい→難しい順で並びます。
データ: `DanmakuApp/Resources/official_stages.json`（`python3 tools/make_official_stages.py` で再生成）。

**ボットの結果について**: 自動プレイのボットで「クリアできる並びか」を確認しました（`DanmakuCore` の `StageBot`）。
- 弱ボット = 遅い自機（約 120px/秒）・短い先読み。強ボット = 速い自機（約 210px/秒）・長い先読み。
- ボットは未来の弾を正確に計算できるので、人間より有利です。「強ボットがクリア」＝クリア不可能ではない、という確認です。
- ボス戦は、ボットが避けながら当てるのが苦手なため、削りきれないことがあります（残HPで確認）。人間の方が狙って当てられるはずですが、実際に遊んで判断してください。

**確認のお願い**: 実機で遊んで、クリアできそうか・難易度の並びが自然かを見て、右端の欄にチェックしてください。難しすぎ/易しすぎのステージは、番号を教えてもらえれば調整します。

| ID | 想定難易度 | 名前 | 内容 | 狙い | ボット | 確認 |
|---|---|---|---|---|---|---|
""" + "\n".join(rows) + "\n"
(root / "docs/OFFICIAL_STAGES.md").write_text(doc)
print("ok", len(rows))
