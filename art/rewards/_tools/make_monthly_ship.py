"""月間ランキングで配る自機の色(月ごとの限定色)を、steel の絵の色を部位ごとに置き換えて作る。
部位: 枠・機体(中/影/明)・ハイライト・電飾(と影)・コックピット(と影)・噴射炎(芯/外)。電飾だけコマごとに色を変えられる(3コマ目でキラッと光る)。
使い方: python3 art/rewards/_tools/make_monthly_ship.py art/rewards art/rewards A
  A = holly(2026年12月・聖夜: 赤い機体に雪、金の電飾、緑のコックピット)
  B = pine (案だけ。緑の機体に雪、赤の電飾)"""
import sys, os
from PIL import Image
src, out, variant = sys.argv[1], sys.argv[2], sys.argv[3]
COLORS = ["gold","snow","crimson","emerald","shadow","steel"]
# steel の色 → 部位
ROLE = {"0b0f24":"outline","4a5a8c":"mid","2a3358":"dark","8fa3d9":"light","ff2e6a":"accent",
        "e8f0ff":"hi","a3123f":"accent_d","29e0ff":"cockpit","0a7fa8":"cockpit_d","fff27a":"flame","ff8c1e":"flame_o"}
def h(s): return tuple(int(s[i:i+2],16) for i in (0,2,4))
PAL = {
 "A": {  # 赤い機体に雪が積もる + 緑と金の電飾
  "outline":"1c0508","mid":"c8202f","dark":"7c0d1c","light":"eef2fb","hi":"ffffff",
  "accent":["ffd23c","ffd23c","fff8d8"],"accent_d":["b8860b","b8860b","ffd23c"],
  "cockpit":"5cf08a","cockpit_d":"1e7a3c","flame":"fff4b0","flame_o":"ffa52e"},
 "B": {  # 深い緑(もみの木)に雪 + 赤と金の電飾
  "outline":"03140c","mid":"1f7a44","dark":"0f4426","light":"eef2fb","hi":"ffffff",
  "accent":["ff3a4a","ff3a4a","ffd8dc"],"accent_d":["a3121f","a3121f","ff3a4a"],
  "cockpit":"ffd23c","cockpit_d":"b07a10","flame":"fff4b0","flame_o":"ffa52e"},
}[variant]
def col(role, f):
    v = PAL[role]
    return h(v[f] if isinstance(v, list) else v)
name = {"A":"holly","B":"pine"}[variant]
for m in ["ace","bastion","gemini","lancer","phantom"]:
    d = os.path.join(out, f"{m}_{name}"); os.makedirs(d, exist_ok=True)
    for f in range(3):
        steel = Image.open(f"{src}/{m}_steel/{m}_steel_{f}.png").convert("RGBA")
        img = Image.new("RGBA", (32,32), (0,0,0,0))
        for y in range(32):
            for x in range(32):
                p = steel.getpixel((x,y))
                if p[3] == 0: continue
                role = ROLE.get("%02x%02x%02x" % p[:3])
                if role is None: raise SystemExit(f"unknown color {p} in {m} {f}")
                img.putpixel((x,y), col(role,f) + (p[3],))
        img.save(os.path.join(d, f"{m}_{name}_{f}.png"))
print("ok", name)
