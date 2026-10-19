"""アプリアイコン(1024x1024、透明部分なし)を、ゲームの実際の部品だけで描く。
  - 弾: ゲームと同じ(色つきの円 + 半分の大きさの白い芯、全部同じ大きさ、ゲームの5色)
  - 弾の並び: ゲームの「渦巻き」の式(弾 j の角度 = j*360/n + 発射回数*回転量)をそのまま使い、発射から一定時間後の位置を描く
  - ボス: ゲームと同じ12角の星(中央に暗い穴)  自機: ゲームと同じ三角形(白い芯)
  - 背景: ゲームの背景色から中心を少し明るくしたもの
使い方: python3 tools/make_app_icon.py   → DanmakuApp/Assets.xcassets/AppIcon.appiconset に書き出す"""
import json, math, os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048  # 2倍で描いて縮小(縁をなめらかにする)
OUT = os.path.join(os.path.dirname(__file__), "..", "DanmakuApp", "Assets.xcassets", "AppIcon.appiconset")
BULLET = [(0xFF, 0x6B, 0x9D), (0x5C, 0xE1, 0xE6), (0xFF, 0xD1, 0x66), (0xB2, 0x8D, 0xFF), (0x7C, 0xF2, 0x9C)]
BG = (0x0A, 0x08, 0x18)

F = S / 250.0                       # ゲームの1単位(論理座標)が、アイコン上で何ピクセルか
CX, CY = S * 0.5, S * 0.38          # 弾の発射位置(ボスの位置)
SHIP = (S * 0.5, S * 0.80)

# ゲームの渦巻き: 5色の発射台が、同じ位置から回転量を変えて撃つ
EMITTERS = [dict(color=c, n=2, r=15.0, phase=c * 72.0) for c in range(5)]
SPEED = 1.4 * 60                    # ゲームの速度(1フレームあたり 1.4 → 1秒あたり)
INTERVAL = 0.05                     # 発射の間隔(ゲームの最短)
AGE_MAX = 1.5                      # 最初の弾が出てからの経過時間(秒)

def background():
    img = Image.new("RGB", (S, S))
    px = img.load()
    for y in range(S):
        for x in range(S):
            t = min(1.0, math.hypot(x - CX, y - CY) / (S * 0.75))
            px[x, y] = (int(0x3A + (BG[0] - 0x3A) * t), int(0x2A + (BG[1] - 0x2A) * t), int(0x7A + (BG[2] - 0x7A) * t))
    return img

def spiral_bullets():
    out = []
    shots = int(AGE_MAX / INTERVAL)
    for e in EMITTERS:
        for k in range(shots):
            age = AGE_MAX - k * INTERVAL
            for j in range(e["n"]):
                a = math.radians(e["phase"] + j * 360.0 / e["n"] + k * e["r"])
                out.append((CX + math.cos(a) * SPEED * age * F, CY + math.sin(a) * SPEED * age * F, e["color"]))
    return out

def main():
    img = background()
    r = 6 * F                                    # ゲームの弾の半径(6)
    bullets = [b for b in spiral_bullets() if math.hypot(b[0] - SHIP[0], b[1] - SHIP[1]) > S * 0.17 and math.hypot(b[0] - CX, b[1] - CY) > 30 * F and -r < b[0] < S + r and -r < b[1] < S + r]
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for x, y, c in bullets:
        col = tuple(int(v * 0.5) for v in BULLET[c])
        gd.ellipse([x - r * 1.9, y - r * 1.9, x + r * 1.9, y + r * 1.9], fill=col)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.016))
    img = ImageChops.add(img, glow.point(lambda v: int(v * 0.6)))
    d = ImageDraw.Draw(img)
    for x, y, c in bullets:
        d.ellipse([x - r, y - r, x + r, y + r], fill=BULLET[c])
        h = r * 0.5
        d.ellipse([x - h, y - h, x + h, y + h], fill=(255, 255, 255))
    # ボス(ゲームと同じ12角の星)
    k = S * 0.0040
    def boss(scale):
        pts = []
        for i in range(12):
            a = i * math.pi / 6
            rr = (14 if i % 2 == 1 else 22) * scale
            pts.append((CX + math.cos(a) * rr, CY + math.sin(a) * rr))
        return pts
    halo = Image.new("RGB", (S, S), (0, 0, 0))
    ImageDraw.Draw(halo).polygon(boss(k * 1.3), fill=(0x90, 0x30, 0x68))
    halo = halo.filter(ImageFilter.GaussianBlur(S * 0.025))
    img = ImageChops.add(img, halo)
    d = ImageDraw.Draw(img)
    d.polygon(boss(k), fill=BULLET[0])
    hole = 7 * k
    d.ellipse([CX - hole, CY - hole, CX + hole, CY + hole], fill=BG)
    # 自機(ゲームと同じ三角形)
    u = S * 0.0085
    sx, sy = SHIP
    def sp(px, py): return (sx + (px - 10) * u, sy + (py - 12) * u)
    d.polygon([sp(10, 1), sp(18, 20), sp(10, 16), sp(2, 20)], fill=(0x5C, 0xE1, 0xE6))
    c = 2.5 * u
    d.ellipse([sx - c, sy - c, sx + c, sy + c], fill=(255, 255, 255))
    img = img.resize((1024, 1024), Image.LANCZOS).convert("RGB")  # アルファなし
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, "Icon-1024.png"), "PNG")
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "Icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(OUT, "..", "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("wrote", os.path.abspath(OUT), "bullets:", len(bullets))

main()
