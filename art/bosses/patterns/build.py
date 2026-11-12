"""ボス専用技のプレビューHTMLと仕様書を作る: python3 build.py <出力先.html>"""
import base64, json, os, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); ART = os.path.dirname(HERE); REPO = os.path.dirname(os.path.dirname(ART))
sys.path.insert(0, HERE)
from spec import BULLETS, BOSSES, PATTERNS
b64 = lambda p: 'data:image/png;base64,' + base64.b64encode(open(p, 'rb').read()).decode()
frames, bosses = {}, []
for bid, name, origin in BOSSES:
    fr = {}
    mp = f'{ART}/{bid}/anim.json'; meta = json.load(open(mp)) if os.path.exists(mp) else {}   # コマ数・速さがふつうと違うボス
    for st, n in (('idle', 8), ('windup', 4), ('attack', 4), ('recover', 2)):
        n = meta.get('counts', {}).get(st, n)
        fr['normal:' + st] = [b64(f'{ART}/{bid}/{bid}_{st}_{i}.png') for i in range(n)]
        aw = 'idle_awakened' if st == 'idle' else st + '_awakened'
        fr['awake:' + st] = [b64(f'{ART}/{bid}/{bid}_{aw}_{i}.png') for i in range(n)]
    frames[bid] = fr
    w, h = Image.open(f'{ART}/{bid}/{bid}_idle_0.png').size
    bosses.append(dict(id=bid, name=name, origin=origin, w=w, h=h, ms=meta.get('frame_ms', 120)))
spec = dict(bosses=bosses, patterns=PATTERNS, bullets=BULLETS)
html = open(f'{HERE}/template.html').read()
html = (html.replace('__SPEC__', json.dumps(spec, ensure_ascii=False)).replace('__FRAMES__', json.dumps(frames))
        .replace('__SHIP__', b64(f'{REPO}/art/rewards/ace_steel/ace_steel_1.png')).replace('__ENGINE__', open(f'{HERE}/engine.js').read()))
open(sys.argv[1], 'w').write(html)
print('html', len(html) // 1024, 'KB')

# 仕様書
L = ['# ボス専用の技(限定弾幕パターン)', '',
     '堕天使と同じ仕組みで、**そのボスを選んでいるときだけステージに置ける技**を、ほかのボスに5つずつ。',
     '弾の見た目も、ボスごとに専用のものを使う。動くプレビューは `art/bosses/patterns/`(`python3 build.py 出力.html` で作れる)。', '',
     '## 決まりごと(堕天使と同じ)', '',
     '- `Pattern` に case を足す(並びは変えず、必ず後ろに足す)。`Pattern.<ボス>` の一覧と `bossCharacter` に入れて、そのボスを選んでいるときだけ置けるようにする',
     '- 覚醒すると、同じ技が強くなる(`awakened` を見る)。ぷにまるだけは、覚醒で技そのものが別物になる',
     '- サーバー(`fullsim.ts`)にも同じ計算を入れ、`validate.ts` で「そのボスにだけ置ける技」を検査する。照合は `FixtureExportTests`',
     '- 数値は見栄えで決めたもの。60fps の px/フレーム で書いているので、Swift では 1/120 秒のステップに直す(`v * 60` が px/秒)',
     '- ぷにまるの覚醒の技名は、ショップ・選択画面・未所持のテストプレイでは出さない(秘密の方針)', '',
     '## 専用の弾', '',
     '今の弾は `color` 0〜4(5色)だけなので、弾の見た目を表す番号を足す必要がある(例: `Bullet.look`)。当たり判定は見た目とは別に半径で持つ。', '',
     '| 弾 | ボス | 当たりの半径(px) | 見た目 |', '|---|---|---|---|']
bname = {b[0]: b[1] for b in BOSSES}
for k, v in BULLETS.items():
    L.append(f"| {v['name']}(`{k}`) | {bname[v['boss']]} | {v['r']} | {v['note']} |")
for bid, name, origin in BOSSES:
    L += ['', f'## {name}', '', f'発射位置(絵の中のドット): {origin}', '']
    for i, p in enumerate(PATTERNS[bid], 1):
        L += [f"### {i}. {p['card']}" + ('(看板技)' if p.get('sig') else ''), '',
              f"- case: `{p['id']}`",
              f"- 弾: " + '、'.join(BULLETS[t]['name'] for t in p['bullets']),
              f"- 動き: {p['desc']}",
              f"- 覚醒: {p['awake']}",
              f"- 数値: {p['params']}", '']
L += ['## 避けられるかの注意', '',
      '- 壁の技(九尾「千本鳥居」、死神「デッドライン」)は、通り道を1列ごとに最大80pxまでしかずらさない。画面の端から50px以内には出さない',
      '- 機神のビームは固定から発射まで14フレーム。13px動けば避けられる',
      '- 死神「三日月の大鎌」は、止まってから30フレーム待つので読める。覚醒は2重になるので、刃の列に隙間を2か所あける',
      '- 死神「冥府の鎖」は、伸びる前に20フレーム予告線を出す',
      '- ぷにまる覚醒「位相のずれ」は、移動先に30フレーム前から印を出し、自機から40px以内には出さない(前に話した救済をはじめから入れた)',
      '- ドラゴン「劫火の咆哮」は、炎の帯が自機を追う速さ(0.006rad/フレーム。400px 先で 2.4px/フレーム)を自機より遅くしてある。覚醒のビームは予告50フレーム',
      '- ドラゴン「金剛裂爪」は、走る前に24フレーム予告線を出す。「メテオフォール」は落ちる30フレーム前に上で光る',
      '- 弾数が多い技(魔女「渦潮」、九尾「天気雨」覚醒、ぷにまる「螺旋の腕」、ドラゴン「劫火の咆哮」覚醒)は `DanmakuConfig.maxBullets` と負荷を確認する']
open(f'{REPO}/docs/BOSS_EXCLUSIVE_PATTERNS.md', 'w').write('\n'.join(L) + '\n')
print('doc ok')
