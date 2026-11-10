#!/usr/bin/env python3
"""ドット絵の自機を作る。左半分(8列)を書いて、左右対称に折り返す。
使い方: python3 tools/make_pixel_ship.py [出力フォルダ]   → 案ごとの PNG(等倍・拡大)と、見比べる一覧画像を出す"""
import sys, pathlib
from PIL import Image

PAL = {
    "A": {"O": (12, 18, 46), "B": (70, 130, 230), "L": (140, 200, 255), "H": (255, 255, 255), "D": (36, 70, 150), "C": (120, 255, 240), "F": (255, 150, 40), "Y": (255, 235, 120)},
    "B": {"O": (46, 10, 24), "B": (230, 70, 90), "L": (255, 150, 150), "H": (255, 240, 220), "D": (140, 24, 56), "C": (255, 220, 90), "F": (255, 120, 30), "Y": (255, 240, 130), "G": (255, 200, 60)},
    "C": {"O": (8, 32, 28), "B": (60, 200, 140), "L": (160, 255, 200), "H": (240, 255, 245), "D": (24, 110, 90), "C": (255, 120, 220), "F": (255, 160, 60), "Y": (255, 240, 140)},
}
SHAPES = {
    # 案A「ストライカー」: すっきりした戦闘機
    "A": [
        ".......O", "......OH", "......OL", ".....OBL", ".....OBC", "....OBLC", "....OBBC", "...OBBLB",
        "O..OBBDB", "OO.OBLBD", "OBOOBBDD", "OBLBBBDD", "OBBBDDOO", "ODDO.OFY", ".OO..OFY", ".....OF.",
    ],
    # 案B「フェニックス」: 翼が大きく広がる
    "B": [
        ".......O", "......OH", ".....OBL", "O....OBL", "OO...OBC", "OBO.OBLC", "OBBOOBBC", "OLBBOBLB",
        "OLBBBBBD", "OBBGBBDD", "OBDGGBDD", "ODDOBDDO", ".OO.OBDO", ".....OFY", ".....OFY", "......F.",
    ],
    # 案C「ステルス」: 平たく鋭い
    "C": [
        "........", ".......O", "......OH", "......OL", ".....OBL", ".....OBC", "....OBLC", "...OBBBC",
        "..OBBLBB", ".OBBLBDB", "OBBBBDBD", "OBDDBDDD", "ODOODOOO", "OO..OOFY", ".....OFY", "......F.",
    ],
}

def build(name: str) -> Image.Image:
    rows = SHAPES[name]; pal = PAL[name]
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y, half in enumerate(rows):
        assert len(half) == 8, (name, y, half)
        row = half + half[::-1]
        for x, ch in enumerate(row):
            if ch != ".": img.putpixel((x, y), pal[ch] + (255,))
    return img

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "pixel_ships"); out.mkdir(parents=True, exist_ok=True)
    scale = 16
    sheet = Image.new("RGBA", (len(SHAPES) * (16 * scale + 24) + 24, 16 * scale + 48), (14, 10, 36, 255))
    for i, name in enumerate(SHAPES):
        s = build(name)
        s.save(out / f"ship_{name}.png")
        big = s.resize((16 * scale, 16 * scale), Image.NEAREST)
        sheet.alpha_composite(big, (24 + i * (16 * scale + 24), 24))
    sheet.save(out / "sheet.png")
    print("ok", out)
