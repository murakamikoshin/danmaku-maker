"""ボスのドット絵を描く共通の道具。ぼかしなし。左半分を描いて左右反転で対称にする。"""
from PIL import Image, ImageDraw, ImageChops
import math
W = H = 128

def M():
    return Image.new('L', (W, H), 0)

def sh(m, dx, dy):
    o = Image.new('L', m.size, 0); o.paste(m, (dx, dy)); return o

def union(*ms):
    o = ms[0]
    for m in ms[1:]: o = ImageChops.lighter(o, m)
    return o

def sub(a, b): return ImageChops.subtract(a, b)
def inter(a, b): return ImageChops.darker(a, b)

def mir(pts): return [(127 - x, y) for x, y in pts]

def poly(m, pts, sym=True):
    # 真ん中(63.5)の点は1ドット右へ出して、左右の継ぎ目にすき間ができないようにする
    pts = [(64.5 if abs(x - 63.5) < 0.01 else x, y) for x, y in pts]
    d = ImageDraw.Draw(m); d.polygon(pts, fill=255)
    if sym: d.polygon(mir(pts), fill=255)
    return m

def ell(m, cx, cy, rx, ry, sym=True):
    d = ImageDraw.Draw(m); d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    if sym and abs(cx - 63.5) > 0.6: d.ellipse((127 - cx - rx, cy - ry, 127 - cx + rx, cy + ry), fill=255)
    return m

def line(m, pts, w, sym=True):
    d = ImageDraw.Draw(m); d.line(pts, fill=255, width=w)
    if sym: d.line(mir(pts), fill=255, width=w)
    return m

def rot(pts, cx, cy, a):
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in pts]

def paint(img, m, col):
    img.paste(Image.new('RGBA', img.size, col + (255,)), (0, 0), m)

def outline_of(m):
    return sub(union(sh(m, 1, 0), sh(m, -1, 0), sh(m, 0, 1), sh(m, 0, -1)), m)

def part(img, m, base, shade=None, light=None, ol=None, sw=3, lw=1, hl=None):
    """形 m を塗る。上から光が当たる: 上の縁が明るく、下の縁が暗い。ol はまわりの1ドットの輪郭"""
    if ol is not None: paint(img, outline_of(m), ol)
    paint(img, m, base)
    if shade is not None: paint(img, sub(m, sh(m, 0, -sw)), shade)
    if light is not None: paint(img, sub(m, sh(m, 0, lw)), light)
    if hl is not None:  # 内側のつや(上の縁から1ドット下)
        paint(img, inter(sub(sh(m, 0, lw), sh(m, 0, lw + 1)), m), hl)

def px(img, x, y, col, sym=True):
    if 0 <= x < W and 0 <= y < H:
        img.putpixel((int(x), int(y)), col + (255,))
        if sym: img.putpixel((127 - int(x), int(y)), col + (255,))

def mirror_left(img):
    L = img.crop((0, 0, 64, H)); img.paste(L.transpose(Image.FLIP_LEFT_RIGHT), (64, 0))
    return img

def offset(img, dx, dy):
    o = Image.new('RGBA', img.size, (0, 0, 0, 0)); o.paste(img, (dx, dy)); return o

def remap(img, table):
    """色の置き換え(パレット内で暗くするなど)。table: {元の色: 新しい色}"""
    px_ = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px_[x, y]
            if a and (r, g, b) in table: px_[x, y] = table[(r, g, b)] + (a,)
    return img

def colors(img):
    return sorted({c[:3] for c in img.getdata() if c[3]})

def glow_orb(img, cx, cy, r, ramp, sym=True):
    """光る核: ramp は外→内の色。真ん中に白い点"""
    for i, col in enumerate(ramp):
        rr = r - i * max(1, r // len(ramp))
        if rr <= 0: break
        m = ell(M(), cx, cy, rr, rr, sym); paint(img, m, col)

# ---- 堕天使に合わせた描き方(細身の等身・暗い色が主体・放射する細い線) ----
CX = 63.5

def rays(img, root, a0, a1, n, r0, r1, body, tip, tiplen=4, wobble=None, sym=True, width=1):
    """root から角度 a0〜a1(度)の扇形に、細い線を n 本。先端だけ差し色"""
    for i in range(n):
        a = math.radians(a0 + (a1 - a0) * i / max(1, n - 1))
        rr = r1 - (wobble[i % len(wobble)] if wobble else 0)
        x0, y0 = root[0] + math.cos(a) * r0, root[1] + math.sin(a) * r0
        x1, y1 = root[0] + math.cos(a) * rr, root[1] + math.sin(a) * rr
        xm, ym = root[0] + math.cos(a) * (rr - tiplen), root[1] + math.sin(a) * (rr - tiplen)
        paint(img, line(M(), [(x0, y0), (xm, ym)], width, sym), body)
        paint(img, line(M(), [(xm, ym), (x1, y1)], width, sym), tip)

def fan(img, root, a0, a1, r1, cols, ol, layers=3):
    """羽根・尾のような扇形の面。外側ほど暗い帯で塗り分ける(堕天使の翼の塗り)"""
    for li in range(layers):
        rr = r1 * (1 - li * 0.22)
        pts = [root]
        for k in range(13):
            a = math.radians(a0 + (a1 - a0) * k / 12)
            jag = 0 if k % 2 == 0 else -3
            pts.append((root[0] + math.cos(a) * (rr + jag), root[1] + math.sin(a) * (rr + jag)))
        m = poly(M(), pts)
        part(img, m, cols[min(li, len(cols) - 1)], ol=ol if li == 0 else None)

def robe(img, c, top=34, bot=98, wtop=8, wbot=17, hem_jag=True):
    """細身の長いローブ。c: dict(ol, d, m, l, acc)"""
    pts = [(CX, top), (CX - wtop, top + 1), (CX - wtop - 3, top + 6), (CX - wtop - 4, top + 26),
           (CX - wbot + 2, bot - 18), (CX - wbot, bot)]
    if hem_jag:
        x = CX - wbot
        while x < CX - 2:
            pts.append((x + 2, bot - 3)); pts.append((x + 4, bot)); x += 4
    pts.append((CX, bot))
    m = poly(M(), pts)
    part(img, m, c['m'], shade=c['d'], light=c['l'], ol=c['ol'], sw=6)
    # 衣のひだ
    for x0, x1 in ((CX - 6, CX - 9), (CX - 11, CX - 14)):
        paint(img, inter(line(M(), [(x0, top + 14), (x1, bot - 4)], 1), m), c['d'])
    return m

def head(img, c, cy=25, hair_len=56, hair_w=10):
    """顔と長い髪。c: dict(ol, skin, skin2, hair, hair2, hairl, eye)"""
    m = poly(M(), [(CX, cy - 9), (CX - 6, cy - 8), (CX - hair_w + 2, cy - 3), (CX - hair_w, cy + 8),
                   (CX - hair_w + 1, hair_len), (CX - hair_w + 5, hair_len - 4), (CX - 6, cy + 10)])
    part(img, m, c['hair'], shade=c['hair2'], light=c['hairl'], ol=c['ol'], sw=4)
    paint(img, poly(M(), [(CX - 2, cy + 5), (CX - 2, cy + 11), (CX, cy + 11), (CX, cy + 5)]), c['skin2'])
    f = ell(M(), CX, cy, 5, 6)
    part(img, f, c['skin'], shade=c['skin2'], ol=c['ol'], sw=2)
    bang = poly(M(), [(CX, cy - 7), (CX - 6, cy - 6), (CX - 6, cy + 1), (CX - 4, cy - 3), (CX - 2, cy - 1), (CX - 1, cy - 4)])
    part(img, bang, c['hair'], shade=c['hair2'], light=c['hairl'], sw=1)
    for x, y in ((CX - 3.5, cy + 1), (CX - 2.5, cy + 1), (CX - 3.5, cy + 2)):
        px(img, x, y, c['eye'])
    px(img, CX - 2.5, cy + 2, c['eyel'])
    px(img, CX - 0.5, cy + 4, c['skin2'])
