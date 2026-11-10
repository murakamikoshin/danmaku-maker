# -*- coding: utf-8 -*-
"""art/bosses/<ID>/<ID>_<状態>[_awakened]_<コマ>.png を横に並べて、DanmakuApp/Resources/Bosses/<ID>_<状態>[_awakened]_sheet.png にする。
状態は windup(4コマ)・attack(4コマ)・recover(2コマ)。ぷにまるの通常の待機は、ほかの状態と同じ幅(136)の絵に差し替える。
使い方: python3 tools/make_boss_state_sheets.py"""
import pathlib
from PIL import Image
root = pathlib.Path(__file__).resolve().parent.parent
out = root / "DanmakuApp/Resources/Bosses"
for i in ["fallen_angel", "kitsune", "ice", "reaper", "witch", "mech", "puni", "hire"]:
    for suf in ["", "_awakened"]:
        for st, n in [("windup", 4), ("attack", 4), ("recover", 2)]:
            fr = [Image.open(root / f"art/bosses/{i}/{i}_{st}{suf}_{k}.png").convert("RGBA") for k in range(n)]
            w, h = fr[0].size
            sheet = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
            for k, f in enumerate(fr):
                sheet.paste(f, (k * w, 0))
            sheet.save(out / f"{i}_{st}{suf}_sheet.png")
# 待機(8コマ)。通常は <ID>_idle_sheet.png、覚醒は <ID>_awakened_idle_sheet.png(ぷにまるの通常も、ほかの状態と同じ幅の絵を使う)
for i in ["fallen_angel", "kitsune", "ice", "reaper", "witch", "mech", "puni", "hire"]:
    for src, dst in [("idle", f"{i}_idle_sheet.png"), ("idle_awakened", f"{i}_awakened_idle_sheet.png")]:
        fr = [Image.open(root / f"art/bosses/{i}/{i}_{src}_{k}.png").convert("RGBA") for k in range(8)]
        w, h = fr[0].size
        sheet = Image.new("RGBA", (w * 8, h), (0, 0, 0, 0))
        for k, f in enumerate(fr):
            sheet.paste(f, (k * w, 0))
        sheet.save(out / dst)
