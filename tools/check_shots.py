# -*- coding: utf-8 -*-
"""撮ったスクリーンショットのうち、アプリの画面になっていないもの(ホーム画面・真っ白)を消す。消したものは、撮影スクリプトをもう一度流すと撮り直される。
アプリの画面は暗い背景なので、暗い画素が3割に満たないものを失敗とみなす。使い方: python3 tools/check_shots.py <フォルダ> [言語…]"""
import sys, pathlib
from PIL import Image
folder = pathlib.Path(sys.argv[1])
langs = sys.argv[2:] or ["es", "de", "fr", "pt-BR", "ru", "ko", "zh-Hans", "zh-Hant"]
bad = []
# ホーム画面(一覧)かどうか: 日本語のホーム画面と、薄い絵の差が小さければ「ホーム画面」。01 以外がホーム画面のままなら、画面を開けていない失敗
ref = Image.open(folder / "ja_01_home.png").convert("L").resize((45, 97)) if (folder / "ja_01_home.png").exists() else None
def homelike(img):
    if ref is None:
        return None
    a = list(img.convert("L").resize((45, 97)).getdata()); b = list(ref.getdata())
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a) < 12
for f in sorted(folder.glob("*.png")):
    if f.name.startswith(".") or f.name.split("_")[0] not in langs:
        continue
    im = Image.open(f).convert("L").resize((90, 195))
    px = list(im.getdata())
    dark = sum(1 for v in px if v < 60) / len(px)
    key = f.name.split("_", 1)[1]
    h = homelike(Image.open(f))
    wrong = dark < 0.30 or (h is not None and (not key.startswith("01") and h))
    if wrong:
        bad.append(f.name); f.unlink()
print("消した:", bad)
