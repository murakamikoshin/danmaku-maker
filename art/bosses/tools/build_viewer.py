"""ボス図鑑のHTML(全コマを埋め込み)を作る: python3 build_viewer.py <出力先.html>"""
import base64, json, sys, os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = [('fallen_angel','堕天使','両手のオーブ'),('kitsune','九尾の巫女','尻尾の付け根'),('witch','深海の魔女','帽子の提灯'),
     ('mech','機神','胸のコアアイ'),('ice','雪の女王','背後の結晶'),('reaper','死神','頭蓋の目'),('hire','金魚姫','ポイ・金魚の手'),('puni','ぷにまる','本体')]
ACTS = [('idle','待機',8,'loop'),('windup','構え',4,'once'),('attack','技中',4,'loop'),('recover','硬直',2,'once')]
data = []
for bid, name, core in B:
    fr = {}
    for a, _, n, _ in ACTS:
        for form, suf in (('normal', ''), ('awake', '_awakened')):
            fr[f'{form}:{a}'] = ['data:image/png;base64,' + base64.b64encode(open(f'{ROOT}/{bid}/{bid}_{a}{suf}_{i}.png', 'rb').read()).decode() for i in range(n)]
    w, h = Image.open(f'{ROOT}/{bid}/{bid}_idle_0.png').size
    data.append(dict(id=bid, name=name, core=core, w=w, h=h, frames=fr))
acts = [dict(id=a, label=l, n=n, mode=m) for a, l, n, m in ACTS]
html = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'viewer_template.html')).read()
html = html.replace('__DATA__', json.dumps(data, ensure_ascii=False)).replace('__ACTS__', json.dumps(acts, ensure_ascii=False))
open(sys.argv[1], 'w').write(html)
print(len(html) // 1024, 'KB')
