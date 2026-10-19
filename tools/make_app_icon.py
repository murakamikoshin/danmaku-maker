"""アプリアイコン(1024x1024、透明部分なし)を描く。ゲーム内の弾と自機と同じ配色。
使い方: python3 tools/make_app_icon.py   → DanmakuApp/Assets.xcassets/AppIcon.appiconset に書き出す"""
import json, math, os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048  # 2倍で描いて縮小(縁をなめらかにする)
OUT = os.path.join(os.path.dirname(__file__), "..", "DanmakuApp", "Assets.xcassets", "AppIcon.appiconset")

BULLET = [(0xFF, 0x6B, 0x9D), (0x5C, 0xE1, 0xE6), (0xFF, 0xD1, 0x66), (0xB2, 0x8D, 0xFF), (0x7C, 0xF2, 0x9C)]

def radial_background():
    img = Image.new("RGB", (S, S))
    px = img.load()
    cx, cy = S * 0.5, S * 0.40
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - cx, y - cy) / (S * 0.75)
            t = min(1.0, d)
            r = int(0x3A + (0x0A - 0x3A) * t)
            g = int(0x2A + (0x08 - 0x2A) * t)
            b = int(0x7A + (0x18 - 0x7A) * t)
            px[x, y] = (r, g, b)
    return img

def bullet(draw, x, y, r, color):
    draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
    c = r * 0.5
    draw.ellipse([x - c, y - c, x + c, y + c], fill=(255, 255, 255))

def main():
    img = radial_background()
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    d = ImageDraw.Draw(img)
    cx, cy = S * 0.5, S * 0.38
    ship = (S * 0.5, S * 0.78)
    # 渦巻き状に広がる弾(中心から外へ)
    n_arms = 4
    for i in range(0, 34):
        t = i / 33
        radius = S * (0.07 + 0.37 * t)
        for arm in range(n_arms):
            a = arm * 2 * math.pi / n_arms + t * 2.2 * math.pi
            x = cx + math.cos(a) * radius
            y = cy + math.sin(a) * radius * 0.92
            if math.hypot(x - ship[0], y - ship[1]) < S * 0.16:
                continue  # 自機のまわりは空ける
            r = S * (0.010 + 0.022 * t)
            color = BULLET[(arm + i // 8) % len(BULLET)]
            gd.ellipse([x - r * 2.2, y - r * 2.2, x + r * 2.2, y + r * 2.2], fill=tuple(int(c * 0.50) for c in color))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.018))
    img = ImageChops.add(img, glow.point(lambda v: int(v * 0.55)))
    d = ImageDraw.Draw(img)
    for i in range(0, 34):
        t = i / 33
        radius = S * (0.07 + 0.37 * t)
        for arm in range(n_arms):
            a = arm * 2 * math.pi / n_arms + t * 2.2 * math.pi
            x = cx + math.cos(a) * radius
            y = cy + math.sin(a) * radius * 0.92
            if math.hypot(x - ship[0], y - ship[1]) < S * 0.16:
                continue
            r = S * (0.010 + 0.022 * t)
            bullet(d, x, y, r, BULLET[(arm + i // 8) % len(BULLET)])
    # 中心の敵(ピンクの星形)
    pts = []
    for k in range(12):
        a = k * math.pi / 6 - math.pi / 2
        rr = S * (0.075 if k % 2 == 0 else 0.045)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=BULLET[0])
    d.ellipse([cx - S * 0.025, cy - S * 0.025, cx + S * 0.025, cy + S * 0.025], fill=(0x0A, 0x08, 0x18))
    # 自機(シアンの三角と白い芯)
    sx, sy = ship
    h = S * 0.115
    d.polygon([(sx, sy - h), (sx + h * 0.8, sy + h * 0.85), (sx, sy + h * 0.45), (sx - h * 0.8, sy + h * 0.85)], fill=(0x5C, 0xE1, 0xE6))
    r = S * 0.03
    d.ellipse([sx - r, sy - r * 0.2, sx + r, sy + r * 1.8], fill=(255, 255, 255))
    img = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")  # アルファなし
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "Icon-1024.png"), "PNG")
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "Icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("wrote", os.path.abspath(OUT))

main()
