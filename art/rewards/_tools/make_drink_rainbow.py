# 虹色の回復ドリンク(32×32、背景透明、文字なし、黒い縁取りなし)。丸いフラスコに虹の液、金のふた、きらきら
from PIL import Image
W = 32
im = Image.new('RGBA', (W, W), (0, 0, 0, 0))
def put(x, y, c):
    if 0 <= x < W and 0 <= y < W: im.putpixel((x, y), tuple(c) + (255,))
cx, cy, r = 16, 20, 9
# 虹の段(上から): 色・暗い色
BANDS = [((255, 92, 120), (196, 46, 86)), ((255, 160, 70), (210, 108, 40)), ((255, 228, 80), (214, 178, 40)),
         ((110, 224, 120), (52, 164, 84)), ((86, 182, 255), (44, 120, 210)), ((166, 120, 255), (112, 70, 204))]
GLASS, GLASSd = (226, 242, 252), (130, 176, 214)
CAP, CAPd, CAPl = (240, 198, 80), (184, 134, 44), (255, 236, 150)
# 金のふた y3-6
for y in range(3, 7):
    for x in range(cx - 3, cx + 3):
        c = CAP
        if x == cx - 3 or x == cx + 2 or y == 6: c = CAPd
        if x == cx - 2 and y < 6: c = CAPl
        put(x, y, c)
put(cx, 2, CAPl); put(cx - 1, 2, CAP)
# 首
for x in range(cx - 4, cx + 4): put(x, 7, GLASSd)
for y in range(8, 12):
    for x in range(cx - 3, cx + 3): put(x, y, GLASSd if x in (cx - 3, cx + 2) else GLASS)
# 胴: 液面は y=cy-4、そこから下を6色の帯に
top = cy - 4; bot = cy + r
for y in range(cy - r, cy + r + 1):
    for x in range(cx - r - 1, cx + r + 1):
        dx, dy = x - cx + 0.5, y - cy
        d = (dx * dx + dy * dy) ** 0.5
        if d > r + 0.4: continue
        if d > r - 0.8: c = GLASSd
        elif y < top: c = GLASS
        else:
            i = min(5, (y - top) * 6 // (bot - top))
            c, cd = BANDS[i]
            if dx > 3.5 or (dx > 1 and dy > r - 4): c = cd
        put(x, y, c)
# 液面のきらめき
for x in range(cx - 7, cx + 7, 3): put(x, top, (255, 255, 255))
# ガラスの光
for x, y in [(cx - 6, cy - 4), (cx - 6, cy - 3), (cx - 5, cy - 6), (cx - 7, cy), (cx - 7, cy + 1)]: put(x, y, (255, 255, 255))
# 中の小さな星のあわ
for x, y in [(cx + 1, cy + 1), (cx - 3, cy + 5), (cx + 4, cy - 2)]: put(x, y, (255, 255, 255))
im.save('drink_rainbow.png')  # art/rewards/drink_rainbow/ に置く
bg = Image.new('RGBA', (W, W), (16, 12, 28, 255)); bg.alpha_composite(im)
bg.resize((256, 256), Image.NEAREST).save('drink_rainbow_preview.png')
