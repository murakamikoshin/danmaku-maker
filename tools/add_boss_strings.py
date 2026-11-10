# -*- coding: utf-8 -*-
"""ボス(キャラクター)の名前・技の名前・説明を、Localizable.xcstrings の10言語に書き込む。何度流しても同じ結果。
使い方: python3 tools/add_boss_strings.py   (BOSSES に足したぶんだけ書く。九尾は add_kitsune で入れ済みの値を持つ)"""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent.parent / 'DanmakuApp/Localizable.xcstrings'
L = ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant']
SECT = ['{b}: Techniken (nur mit diesem Aussehen)', '{b} moves (only with this look)', '{b}: técnicas (solo con este aspecto)', '{b} : techniques (uniquement avec cet aspect)',
        '{b}の技(この見た目のときだけ)', '{b}의 기술 (이 모습일 때만)', '{b}: golpes (só com este visual)', '{b}: приёмы (только с этим обликом)', '{b}的招式(仅限此外观)', '{b}的招式(僅限此外觀)']
DESC = ['{b}: 5 Techniken und Erwachen', '{b} — 5 moves, and it awakens', '{b}: 5 técnicas y despertar', '{b} : 5 techniques et éveil', '{b} ― 5つの技と、覚醒', '{b} ― 기술 5개와 각성',
        '{b}: 5 golpes e despertar', '{b}: 5 приёмов и пробуждение', '{b} ― 5种招式与觉醒', '{b} ― 5種招式與覺醒']
JOINS = [(', ', ' und '), (', ', ' and '), (', ', ' y '), (', ', ' et '), ('・', None), (', ', None), (', ', ' e '), (', ', ' и '), ('、', None), ('、', None)]
TAILS = ['. Nach dem Erwachen werden die Techniken stärker – du wählst, wann.', '. Moves get stronger after it awakens, and you choose when it awakens.',
         '. Tras despertar, las técnicas se hacen más fuertes y tú eliges cuándo.', ". Après l'éveil, les techniques se renforcent, et vous choisissez quand.",
         '。覚醒すると技が強くなり、覚醒する段階は自分で決められます。', '. 각성하면 기술이 강해지고, 각성 단계는 직접 정할 수 있어요.', '. Depois de despertar, os golpes ficam mais fortes, e você escolhe quando.',
         '. После пробуждения приёмы сильнее, а момент выбираешь ты.', '。觉醒后招式会变强，觉醒的阶段可自行设定。', '。覺醒後招式會變強，覺醒的階段可自行設定。']

# 並びは L と同じ(de, en, es, fr, ja, ko, pt-BR, ru, zh-Hans, zh-Hant)
BOSSES = {
    7: dict(
        name=['Schneekönigin', 'Snow Queen', 'Reina de las Nieves', 'Reine des neiges', '雪の女王', '눈의 여왕', 'Rainha da Neve', 'Снежная королева', '雪之女王', '雪之女王'],
        moves=[
            ('iceCage', ['Kristallkäfig', 'Crystal Cage', 'Jaula de cristal', 'Cage de cristal', '結晶の檻', '결정의 감옥', 'Gaiola de cristal', 'Хрустальная клетка', '结晶之笼', '結晶之籠']),
            ('iceIcicles', ['Eiszapfenfall', 'Icicle Fall', 'Caída de carámbanos', 'Chute de stalactites', 'アイシクル・フォール', '아이시클 폴', 'Queda de pingentes', 'Падение сосулек', '冰柱坠落', '冰柱墜落']),
            ('iceBlizzard', ['Schneesturm', 'Whiteout', 'Ventisca', 'Tempête de neige', 'ホワイトアウト', '화이트아웃', 'Nevasca', 'Метель', '暴风雪', '暴風雪']),
            ('iceFreeze', ['Eisstarre der Zeit', 'Frozen Time', 'Congelación del tiempo', 'Gel du temps', '時の氷結', '시간의 빙결', 'Congelamento do tempo', 'Заморозка времени', '时之冰结', '時之冰結']),
            ('iceMirror', ['Eisspiegel', 'Diamond Dust', 'Espejo de hielo', 'Miroir de glace', '氷鏡', '얼음 거울', 'Espelho de gelo', 'Ледяное зеркало', '冰镜', '冰鏡']),
        ]),
}

def mk(vals):
    return {'extractionState': 'manual', 'localizations': {l: {'stringUnit': {'state': 'translated', 'value': v}} for l, v in zip(L, vals)}}

d = json.loads(P.read_text(encoding='utf-8'))
S = d['strings']
for num, bd in BOSSES.items():
    S[f'enemy.boss.{num}'] = mk(bd['name'])
    S[f'editor.pattern.bosssection.{num}'] = mk([t.format(b=n) for t, n in zip(SECT, bd['name'])])
    S[f'shop.boss.{num}.desc'] = mk([t.format(b=n) for t, n in zip(DESC, bd['name'])])
    moves = []
    for i in range(len(L)):
        ns = [m[1][i] for m in bd['moves']]
        sep, last = JOINS[i]
        moves.append(sep.join(ns[:-1]) + (last or sep) + ns[-1] + TAILS[i])
    S[f'shop.boss.{num}.moves'] = mk(moves)
    for key, names in bd['moves']:
        S[f'pattern.{key}'] = mk(names)
P.write_text(json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ': ')), encoding='utf-8')
print('ok', list(BOSSES))
