# -*- coding: utf-8 -*-
"""撮ったスクリーンショットのうち、アプリの画面になっていないもの(ホーム画面・真っ白)を消す。消したものは、撮影スクリプトをもう一度流すと撮り直される。
アプリの画面は暗い背景なので、暗い画素が3割に満たないものを失敗とみなす。使い方: python3 tools/check_shots.py <フォルダ> [言語…]"""
import sys, pathlib
from PIL import Image
folder = pathlib.Path(sys.argv[1])
langs = sys.argv[2:] or ["es", "de", "fr", "pt-BR", "ru", "ko", "zh-Hans", "zh-Hant"]
bad = []
for f in sorted(folder.glob("*.png")):
    if f.name.startswith(".") or f.name.split("_")[0] not in langs:
        continue
    im = Image.open(f).convert("L").resize((90, 195))
    px = list(im.getdata())
    dark = sum(1 for v in px if v < 60) / len(px)
    if dark < 0.30:
        bad.append(f.name); f.unlink()
print("消した:", bad)
