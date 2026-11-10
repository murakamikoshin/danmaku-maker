#!/usr/bin/env python3
"""公式サンプルステージ30本を生成する。
出力: DanmakuApp/Resources/official_stages.json（アプリが読み込む）
使い方: python3 tools/make_official_stages.py
"""
import json, pathlib

def E(t, x=.5, y=.2, s=0, e=None, i=1, c=8, v=2, r=0, k=0, ph=0):
    return dict(t=t, x=x, y=y, s=s, e=e if e is not None else 999, i=i, c=c, v=v, r=r, k=k, ph=ph)

def survive(d, ems):
    return dict(mode="survive", durationSec=d, bossHp=None, bossMove=None,
                emitters=[{**m, "e": min(m["e"], d)} for m in ems], formatVersion=1)

def boss(d, hp, mv, ems):
    return dict(mode="boss", durationSec=d, bossHp=hp, bossMove=mv,
                emitters=[{**m, "e": d} for m in ems], formatVersion=1)

# (id, 難易度1-5, 名前ja, 名前en, 狙いja, 狙いen, stage)
S = []
def add(level, ja, en, aim_ja, aim_en, stage):
    S.append((f"o{len(S)+1:02d}", level, ja, en, aim_ja, aim_en, stage))

# ---- 難易度1：入門 ----
add(1, "はじめての渦", "First Vortex", "渦巻きの弾の間をゆっくり抜ける練習。操作に慣れる。", "Slip between slow spiral arms. Learn the controls.",
    survive(20, [E("spiral", y=.25, i=.12, c=3, v=1.8, r=11, k=1)]))
add(1, "にわか雨", "Passing Shower", "雨を避けながら、途中から来る自機狙いを見る。", "Dodge rain, then notice the aimed shots that join later.",
    survive(20, [E("rain", y=0, i=.18, c=2, v=2.2, k=1), E("aim", y=.15, s=5, i=1.5, c=3, v=2.5, r=30, k=2)]))
add(1, "見てるぞ", "I See You", "自機を狙う弾は、少し動けば当たらないと知る。", "Aimed shots miss if you keep moving a little.",
    survive(20, [E("aim", x=.2, y=.15, i=.9, c=5, v=3, r=40, k=0), E("aim", x=.8, y=.15, s=.45, i=.9, c=5, v=3, r=40, k=3)]))
add(1, "ゆらゆら扇", "Swaying Fan", "左右に振れる扇の隙間を見つける。", "Find the gaps in a fan swinging side to side.",
    survive(20, [E("sweep", y=.1, i=.2, c=3, v=2, r=50, k=4)]))
add(1, "ちびボス", "Little Boss", "ボス戦の入門。撃ちながら避ける。HPが少ない。", "Boss intro. Dodge while your auto-fire works. Low HP.",
    boss(30, 150, 0, [E("ring", y=.18, i=.9, c=10, v=1.6, r=7, k=0), E("aim", y=.18, i=1.4, c=3, v=2.2, r=20, k=2)]))
# ---- 難易度2：やさしい ----
add(2, "輪っか", "Rings", "ゆっくり広がる輪の隙間をくぐる。", "Pass through the gaps in slowly expanding rings.",
    survive(30, [E("ring", y=.2, i=1.2, c=12, v=1.6, r=8, k=0)]))
add(2, "雨と渦", "Rain & Spiral", "雨を避けつつ、渦が増えてくるのに対応する。", "Handle rain while a spiral starts up.",
    survive(30, [E("rain", y=0, i=.3, c=2, v=2, k=1), E("spiral", y=.2, s=4, i=.2, c=2, v=1.6, r=14, k=3)]))
add(2, "ダブル渦", "Double Vortex", "逆回りの2つの渦。中央を通るか、外を回るか。", "Two counter-rotating spirals. Weave through the middle or go around.",
    survive(30, [E("spiral", x=.3, y=.2, i=.15, c=2, v=1.8, r=13, k=1), E("spiral", x=.7, y=.2, i=.15, c=2, v=1.8, r=-13, k=2)]))
add(2, "土砂降り", "Downpour", "密度の高い雨の中で、自機狙いも避ける。", "Dense rain plus aimed shots.",
    survive(30, [E("rain", y=0, i=.12, c=3, v=2.6, k=1), E("aim", y=.15, i=1.2, c=3, v=2.4, r=24, k=2)]))
add(2, "扇風機", "Electric Fans", "左右2つの扇が同時に振れる。", "Two fans swinging at once, left and right.",
    survive(30, [E("sweep", x=.25, y=.1, i=.18, c=3, v=2.6, r=60, k=1), E("sweep", x=.75, y=.1, i=.18, c=3, v=2.6, r=60, k=3)]))
# ---- 難易度3：ふつう ----
add(3, "ゆらゆらボス", "Swaying Boss", "段階ごとに攻撃が変わるボス。動く的に当てる。", "A swaying boss whose attack changes each phase.",
    boss(60, 200, 1, [E("aim", y=.18, i=.7, c=3, v=2.2, r=30, k=2, ph=1), E("ring", y=.18, i=.8, c=12, v=1.8, r=9, k=0, ph=2), E("spiral", y=.18, i=.12, c=3, v=2, r=12, k=3, ph=3)]))
add(3, "花火大会", "Fireworks", "時間差で上がる花火（輪）のリズムをつかむ。", "Read the rhythm of staggered ring fireworks.",
    survive(45, [E("ring", x=.3, i=.9, c=14, v=2, r=6, k=0), E("ring", x=.7, s=.45, i=.9, c=14, v=2, r=-6, k=2)]))
add(3, "三方向", "Crossfire", "3方向からの自機狙い。立ち位置を決めて動く。", "Aimed shots from three directions.",
    survive(45, [E("aim", x=.1, y=.1, i=1, c=4, v=2.6, r=36, k=0), E("aim", x=.9, y=.1, s=.5, i=1, c=4, v=2.6, r=36, k=3), E("aim", x=.5, y=.05, s=1, i=1.2, c=4, v=2.8, r=30, k=1)]))
add(3, "回転木馬", "Carousel", "細かい渦と、逆回りの大きな輪の組み合わせ。", "A fine spiral combined with a big counter-rotating ring.",
    survive(45, [E("spiral", y=.3, i=.1, c=6, v=1.7, r=7, k=1), E("ring", y=.3, s=3, i=1.6, c=18, v=2.2, r=-10, k=2)]))
add(3, "時間差攻撃", "Staggered Attack", "次々に新しい攻撃が加わる。慌てずに順応する。", "New attacks keep joining. Adapt calmly.",
    survive(45, [E("spiral", y=.2, e=20, i=.16, c=3, v=1.8, r=11, k=1), E("aim", y=.15, s=8, i=1, c=4, v=2.6, r=34, k=2), E("ring", x=.5, y=.25, s=18, i=1.3, c=16, v=2, r=7, k=0), E("sweep", y=.1, s=28, i=.2, c=3, v=2.4, r=60, k=3)]))
# ---- 難易度4：むずかしい ----
add(4, "三段変化のボス", "Three-Phase Boss", "3段階で攻撃が激しくなる本格的なボス戦。", "A proper three-phase boss fight.",
    boss(90, 400, 1, [E("aim", y=.2, i=.6, c=5, v=2.6, r=50, k=2, ph=1), E("ring", y=.2, i=.55, c=18, v=2, r=9, k=0, ph=2), E("spiral", y=.2, i=.09, c=4, v=2.1, r=13, k=3, ph=3), E("aim", y=.2, i=1.4, c=3, v=3.2, r=20, k=1, ph=3)]))
add(4, "カーテン", "Curtain", "大きく振れる扇と雨の壁。動き続ける。", "A wide sweeping fan plus a wall of rain. Keep moving.",
    survive(60, [E("sweep", y=.08, i=.14, c=4, v=2.4, r=70, k=4), E("rain", y=0, s=10, i=.2, c=2, v=2.2, k=1)]))
add(4, "渦の迷路", "Vortex Maze", "3つの渦が作る迷路を60秒かけて抜ける。", "Navigate a maze of three spirals for 60 seconds.",
    survive(60, [E("spiral", x=.2, y=.2, i=.2, c=2, v=1.8, r=9, k=1), E("spiral", x=.5, y=.15, i=.2, c=2, v=1.8, r=-9, k=2), E("spiral", x=.8, y=.2, i=.2, c=2, v=1.8, r=9, k=3)]))
add(4, "鬼畜・花火大会", "Hellish Fireworks", "花火の密度と速さが上がり、後半に扇が加わる。", "Faster, denser fireworks, then a fan joins late.",
    survive(20, [E("ring", x=.3, i=.7, c=20, v=2.2, r=7, k=0), E("ring", x=.7, s=.35, i=.7, c=20, v=2.2, r=-7, k=2), E("sweep", y=.1, s=6, i=.2, c=3, v=3, r=70, k=1)]))
add(4, "弾の壁", "Wall of Bullets", "3つの輪が作る壁の隙間を見極める。", "Spot the gaps in a wall made by three rings.",
    survive(45, [E("ring", x=.2, i=.8, c=24, v=1.9, r=5, k=0), E("ring", x=.5, s=.27, i=.8, c=24, v=1.9, r=-5, k=2), E("ring", x=.8, s=.54, i=.8, c=24, v=1.9, r=5, k=1)]))
# ---- 難易度5：激ムズ ----
add(5, "高速ボス", "Speedy Boss", "速く動くボス。弾を当てつつ、全段階を耐える。", "A fast-moving boss. Land your shots and survive every phase.",
    boss(120, 500, 2, [E("aim", y=.18, i=.5, c=5, v=2.8, r=45, k=2, ph=1), E("ring", y=.18, i=.5, c=20, v=2.2, r=8, k=0, ph=2), E("sweep", y=.18, i=.2, c=3, v=2.6, r=60, k=1, ph=2), E("spiral", y=.18, i=.08, c=4, v=2.3, r=13, k=3, ph=3), E("aim", y=.18, i=1.1, c=3, v=3.2, r=20, k=1, ph=3)]))
add(5, "嵐", "Storm", "雨・自機狙い・渦が同時に襲う。", "Rain, aimed shots, and a spiral all at once.",
    survive(60, [E("rain", y=0, i=.14, c=3, v=2.6, k=1), E("aim", y=.12, s=3, i=1.1, c=4, v=2.8, r=34, k=2), E("spiral", y=.3, s=8, i=.16, c=3, v=1.8, r=10, k=3)]))
add(5, "星空", "Starry Sky", "ゆっくりだが、画面を埋める大量の輪。", "Slow but screen-filling rings.",
    survive(60, [E("ring", y=.2, i=1.5, c=36, v=1.3, r=5, k=2), E("ring", y=.35, s=.75, i=1.5, c=36, v=1.3, r=-5, k=0)]))
add(5, "連弾ボス", "Barrage Boss", "HP600。長丁場の弾幕を耐えて削り切る。", "HP 600. Survive a long barrage while chipping it down.",
    boss(180, 600, 2, [E("aim", y=.18, i=.45, c=6, v=2.8, r=50, k=2, ph=1), E("spiral", y=.18, i=.1, c=4, v=2, r=11, k=1, ph=1), E("ring", y=.18, i=.45, c=22, v=2.2, r=7, k=0, ph=2), E("sweep", y=.18, i=.16, c=4, v=2.6, r=70, k=4, ph=2), E("spiral", y=.18, i=.07, c=5, v=2.3, r=13, k=3, ph=3), E("ring", y=.18, i=1, c=26, v=1.8, r=-9, k=2, ph=3)]))
add(5, "90秒の試練", "90-Second Trial", "攻撃が3段階で切り替わる、長時間の耐久。", "A long endurance run through three escalating waves.",
    survive(90, [E("spiral", y=.25, e=40, i=.12, c=3, v=1.9, r=11, k=1), E("aim", x=.3, y=.12, s=15, i=.9, c=4, v=2.7, r=34, k=0), E("aim", x=.7, y=.12, s=15.4, i=.9, c=4, v=2.7, r=34, k=3), E("ring", y=.3, s=40, i=1.1, c=22, v=2, r=7, k=2), E("sweep", y=.1, s=55, i=.15, c=4, v=2.6, r=70, k=4)]))
add(5, "鳥籠", "Birdcage", "逆回りの輪と渦が作る籠の中で、90秒生き残る。", "Survive 90 seconds inside a cage of counter-rotating rings and spirals.",
    survive(90, [E("ring", y=.25, i=1, c=20, v=1.8, r=7, k=0), E("spiral", y=.25, s=2, i=.14, c=3, v=1.7, r=-12, k=1), E("rain", y=0, s=20, i=.25, c=2, v=2, k=2), E("aim", y=.1, s=35, i=1.3, c=5, v=2.6, r=30, k=3)]))
add(5, "最終章・ボス", "Final Chapter Boss", "HP800、180秒。すべてを使い切る最終ボス。", "HP 800, 180 seconds. The final boss that uses everything.",
    boss(180, 800, 1, [E("aim", y=.18, i=.5, c=6, v=2.8, r=50, k=2, ph=1), E("ring", y=.18, i=.6, c=20, v=2, r=8, k=0, ph=1), E("spiral", y=.18, i=.09, c=4, v=2.1, r=12, k=3, ph=2), E("sweep", y=.18, i=.16, c=4, v=2.7, r=70, k=1, ph=2), E("ring", y=.18, i=.8, c=28, v=1.9, r=-8, k=2, ph=3), E("spiral", y=.18, i=.07, c=5, v=2.4, r=14, k=4, ph=3), E("aim", y=.18, i=1, c=5, v=3.3, r=24, k=0, ph=3)]))
add(5, "120秒の悪夢", "120-Second Nightmare", "あらゆるパターンが重なり続ける2分間。", "Two minutes of every pattern stacked together.",
    survive(120, [E("spiral", y=.25, i=.12, c=4, v=1.9, r=11, k=1), E("ring", x=.3, y=.2, s=10, i=1, c=18, v=2, r=7, k=0), E("ring", x=.7, y=.2, s=10.5, i=1, c=18, v=2, r=-7, k=2), E("rain", y=0, s=30, i=.2, c=2, v=2.4, k=3), E("aim", y=.1, s=50, i=.8, c=5, v=2.9, r=36, k=4), E("sweep", y=.08, s=75, i=.15, c=4, v=2.7, r=70, k=1)]))
add(5, "弾幕地獄", "Danmaku Hell", "密度が桁違い。見切る目と指の精度が試される。", "Insane density. Tests your eyes and finger precision.",
    survive(120, [E("spiral", x=.3, y=.2, i=.1, c=4, v=1.9, r=9, k=1), E("spiral", x=.7, y=.2, i=.1, c=4, v=1.9, r=-9, k=2), E("ring", y=.3, s=15, i=.9, c=28, v=2, r=5, k=0), E("rain", y=0, s=30, i=.16, c=3, v=2.6, k=3), E("aim", y=.1, s=45, i=.7, c=6, v=3, r=40, k=4), E("sweep", y=.08, s=70, i=.13, c=5, v=2.8, r=75, k=1)]))
add(5, "神の領域", "Divine Realm", "真の最難関。クリアできたら達人。", "The ultimate test. Clear it and you're a master.",
    survive(120, [E("spiral", y=.22, i=.08, c=5, v=2, r=11, k=2), E("ring", x=.2, y=.2, s=8, i=.8, c=26, v=2.1, r=6, k=0), E("ring", x=.8, y=.2, s=8.4, i=.8, c=26, v=2.1, r=-6, k=1), E("rain", y=0, s=25, i=.14, c=3, v=2.8, k=3), E("aim", x=.5, y=.08, s=40, i=.6, c=7, v=3.1, r=44, k=4), E("sweep", y=.08, s=60, i=.12, c=5, v=2.9, r=80, k=2), E("spiral", x=.5, y=.4, s=85, i=.1, c=4, v=2.2, r=-13, k=1)]))

# ---- ボス「堕天使」の見本(ボスは課金/無料チケットで公開できる。遊ぶのは誰でも無料) ----
def angel_boss(d, hp, awaken, ems, look=5):
    return dict(mode="boss", durationSec=d, bossHp=hp, bossMove=0, bossLook=look, awaken=awaken,
                emitters=[{**m, "e": d} for m in ems], formatVersion=1)
add(5, "堕天使の裁き", "Judgment of the Fallen Angel", "堕天使の5つの技。HPが減ると覚醒して、技が強くなる。", "The Fallen Angel's five moves. It awakens and grows stronger as its HP drops.",
    angel_boss(90, 500, 3, [E("angelFeather", i=.5, c=7, v=3.8, k=0, ph=1), E("angelTwin", i=.1, c=4, v=2.3, r=10, k=1, ph=1), E("angelHalo", i=2, c=22, v=4.2, k=2, ph=2),
                           E("angelCross", i=2, c=1, v=2, k=3, ph=2), E("angelParadise", i=1.2, c=23, v=1.05, r=29, k=4, ph=3), E("angelFeather", i=.6, c=8, v=3.8, k=0, ph=3)]))

# ---- ボス「九尾の巫女」の見本 ----
add(5, "九尾の巫女の舞", "Dance of the Nine-Tailed Shrine Maiden", "九尾の巫女の5つの技。HPが減ると覚醒して、技が強くなる。", "The Nine-Tailed Shrine Maiden's five moves. She awakens and grows stronger as her HP drops.",
    angel_boss(90, 500, 3, [E("kitsuneLanterns", i=.1, c=9, v=3.2, k=0, ph=1), E("kitsuneBarrier", i=.65, c=12, v=2, k=1, ph=1), E("kitsuneSunshower", i=.05, c=8, v=2.2, k=2, ph=2),
                           E("kitsuneTorii", i=.45, c=22, v=1.4, r=60, k=3, ph=2), E("kitsuneDance", i=.05, c=9, v=2.2, k=4, ph=3), E("kitsuneLanterns", i=.1, c=9, v=3.2, k=0, ph=3)], look=6))

# ---- ボス「雪の女王」の見本 ----
add(5, "雪の女王の氷晶", "Crystals of the Snow Queen", "雪の女王の5つの技。HPが減ると覚醒して、技が強くなる。", "The Snow Queen's five moves. She awakens and grows stronger as her HP drops.",
    angel_boss(90, 500, 3, [E("iceCage", i=.85, c=6, v=2, k=0, ph=1), E("iceIcicles", i=.85, c=6, v=1, k=1, ph=1), E("iceMirror", i=.35, c=5, v=3, k=2, ph=2),
                           E("iceBlizzard", i=.05, c=8, v=1.6, k=3, ph=2), E("iceFreeze", i=.5, c=20, v=2.5, k=4, ph=3), E("iceCage", i=.85, c=6, v=2, k=0, ph=3)], look=7))

# ---- ボス「死神」の見本 ----
add(5, "死神の収穫", "The Reaper's Harvest", "死神の5つの技。HPが減ると覚醒して、技が強くなる。", "The Reaper's five moves. He awakens and grows stronger as his HP drops.",
    angel_boss(90, 500, 3, [E("reaperScythe", i=2.5, c=28, v=1, k=0, ph=1), E("reaperSouls", i=3.5, c=10, v=1.4, k=1, ph=1), E("reaperDeadline", i=1.15, c=14, v=1, r=56, k=2, ph=2),
                           E("reaperChains", i=1.15, c=3, v=4, k=3, ph=2), E("reaperRiver", i=.15, c=5, v=2.4, k=4, ph=3), E("reaperScythe", i=2.5, c=28, v=1, k=0, ph=3)], look=8))

# ---- ボス「深海の魔女」の見本 ----
add(5, "深海の魔女の誘い", "Lure of the Deep-Sea Witch", "深海の魔女の5つの技。HPが減ると覚醒して、技が強くなる。", "The Deep-Sea Witch's five moves. She awakens and grows stronger as her HP drops.",
    angel_boss(90, 500, 3, [E("witchBubbles", i=.75, c=4, v=1.2, k=0, ph=1), E("witchTentacles", i=.05, c=8, v=2, k=1, ph=1), E("witchInk", i=.85, c=3, v=1, k=2, ph=2),
                           E("witchAbyss", i=.15, c=7, v=1.8, k=3, ph=2), E("witchMaelstrom", i=.05, c=5, v=1.9, k=4, ph=3), E("witchBubbles", i=.75, c=4, v=1.2, k=0, ph=3)], look=9))

assert len(S) == 35, len(S)
out = [dict(id=i, difficulty=lv, name=dict(ja=ja, en=en), aim=dict(ja=aj, en=ae), stage={**st, "name": i}) for (i, lv, ja, en, aj, ae, st) in S]
root = pathlib.Path(__file__).resolve().parent.parent
(root / "DanmakuApp/Resources/official_stages.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
print("wrote", len(out), "stages")
