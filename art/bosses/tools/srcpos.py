"""元のイラストの座標 → ボスの絵(112×112)の中の座標。発射位置や効果の中心を決めるときに使う
使い方: from srcpos import to_frame; to_frame('kitsune', 100, 80, foot=16)"""
import json, os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
def to_frame(bid, sx, sy, foot, size=(112, 112)):
    still = os.path.join(ROOT, bid, 'source', f'{bid}_still.png')
    mp = json.load(open(still + '.map.json')); st = Image.open(still)
    x = (sx - mp['box'][0]) * mp['sc'] + mp.get('pad', 0); y = (sy - mp['box'][1]) * mp['sc'] + mp.get('pad', 0)
    return (round(x + (size[0] - st.width) // 2), round(y + size[1] - st.height - foot))
