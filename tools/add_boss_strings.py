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
    8: dict(
        name=['Sensenmann', 'Reaper', 'Segador', 'Faucheuse', '死神', '사신', 'Ceifador', 'Жнец', '死神', '死神'],
        moves=[
            ('reaperScythe', ['Mondsichelsense', 'Crescent Scythe', 'Guadaña creciente', 'Faux croissant', '三日月の大鎌', '초승달 대낫', 'Foice crescente', 'Серп-коса', '新月大镰', '新月大鐮']),
            ('reaperSouls', ['Wandernde Seelen', 'Wandering Souls', 'Almas errantes', 'Âmes errantes', 'さまよう魂', '떠도는 영혼', 'Almas errantes', 'Блуждающие души', '游荡之魂', '遊蕩之魂']),
            ('reaperChains', ['Ketten der Unterwelt', 'Chains of the Underworld', 'Cadenas del inframundo', 'Chaînes des enfers', '冥府の鎖', '명부의 사슬', 'Correntes do submundo', 'Цепи подземного мира', '冥府之锁', '冥府之鎖']),
            ('reaperDeadline', ['Deadline', 'Deadline', 'Fecha límite', 'Date limite', 'デッドライン', '데드라인', 'Prazo final', 'Крайний срок', '死线', '死線']),
            ('reaperRiver', ['Überfahrt über den Styx', 'Crossing the Styx', 'Cruce del Estigia', 'Traversée du Styx', '三途の渡し', '삼도천 건너기', 'Travessia do Estige', 'Переправа через Стикс', '渡过三途川', '渡過三途川']),
        ]),
    9: dict(
        name=['Tiefsee-Hexe', 'Deep-Sea Witch', 'Bruja del abismo', 'Sorcière des abysses', '深海の魔女', '심해의 마녀', 'Bruxa das profundezas', 'Ведьма глубин', '深海魔女', '深海魔女'],
        moves=[
            ('witchAbyss', ['Lockruf der Laterne', 'Lure of the Lantern', 'El señuelo del farol', "L'appât de la lanterne", '提灯の誘い', '초롱의 유혹', 'Isca da lanterna', 'Зов фонаря', '灯笼的诱惑', '燈籠的誘惑']),
            ('witchBubbles', ['Wachsende Blasen', 'Swelling Bubbles', 'Burbujas crecientes', 'Bulles gonflantes', '膨らむ泡', '부푸는 거품', 'Bolhas crescentes', 'Растущие пузыри', '膨胀气泡', '膨脹氣泡']),
            ('witchTentacles', ['Umarmung der acht Arme', 'Embrace of Eight Arms', 'Abrazo de ocho brazos', 'Étreinte des huit bras', '八腕の抱擁', '여덟 팔의 포옹', 'Abraço de oito braços', 'Объятия восьми рук', '八臂拥抱', '八臂擁抱']),
            ('witchMaelstrom', ['Mahlstrom', 'Maelstrom', 'Remolino', 'Maelström', 'メイルシュトローム', '메일스트롬', 'Redemoinho', 'Мальстрём', '大漩涡', '大漩渦']),
            ('witchInk', ['Vorhang der Schwarzen Flut', 'Veil of the Black Tide', 'Velo de la marea negra', 'Voile de la marée noire', '黒潮の帳', '흑조의 장막', 'Véu da maré negra', 'Завеса чёрного прилива', '黑潮之帷', '黑潮之帷']),
        ]),
    10: dict(
        name=['Maschinengott', 'Mech Deity', 'Dios mecánico', 'Dieu mécanique', '機神', '기신', 'Deus mecânico', 'Механический бог', '机神', '機神'],
        moves=[
            ('mechLockOn', ['Kernauge-Zielerfassung', 'Core-Eye Lock-On', 'Fijación del ojo núcleo', "Verrouillage de l'œil-noyau", 'コアアイ・ロックオン', '코어 아이 락온', 'Mira do olho-núcleo', 'Захват ядра-глаза', '核心之眼·锁定', '核心之眼·鎖定']),
            ('mechMissiles', ['Mikroraketen', 'Micro Missiles', 'Micromisiles', 'Micro-missiles', 'マイクロミサイル', '마이크로 미사일', 'Micromísseis', 'Микроракеты', '微型导弹', '微型飛彈']),
            ('mechGatling', ['Gatling-Fächer', 'Gatling Sweep', 'Barrido Gatling', 'Balayage Gatling', 'ガトリング・スイープ', '개틀링 스위프', 'Varredura Gatling', 'Веер Гатлинга', '加特林扫射', '加特林掃射']),
            ('mechGrid', ['Hexa-Laser', 'Hexa Laser', 'Hexaláser', 'Hexa-laser', 'ヘキサ・レーザー', '헥사 레이저', 'Hexalaser', 'Гекса-лазер', '六角激光', '六角雷射']),
            ('mechOverload', ['Überlastung', 'Overload', 'Sobrecarga', 'Surcharge', 'オーバーロード', '오버로드', 'Sobrecarga', 'Перегрузка', '过载', '過載']),
        ]),
    11: dict(
        secret=True,
        name=['Punimaru', 'Punimaru', 'Punimaru', 'Punimaru', 'ぷにまる', '푸니마루', 'Punimaru', 'Пунимару', '噗尼丸', '噗尼丸'],
        moves=[
            ('puniPoyon', ['Poyon', 'Poyon', 'Poyon', 'Poyon', 'ぽよん', '뽀용', 'Poyon', 'Пойон', '噗哟', '噗喲']),
            ('puniShower', ['Puni-Puni-Dusche', 'Puni-Puni Shower', 'Ducha Puni-Puni', 'Douche Puni-Puni', 'ぷにぷにシャワー', '푸니푸니 샤워', 'Chuveiro Puni-Puni', 'Пуни-пуни душ', '噗尼噗尼淋浴', '噗尼噗尼淋浴']),
            ('puniKorokoro', ['Korokoro', 'Korokoro', 'Korokoro', 'Korokoro', 'ころころ', '데굴데굴', 'Korokoro', 'Корокоро', '咕噜咕噜', '咕嚕咕嚕']),
            ('puniPurupuru', ['Purupuru', 'Purupuru', 'Purupuru', 'Purupuru', 'ぷるぷる', '푸루푸루', 'Purupuru', 'Пурупуру', '噗噜噗噜', '噗嚕噗嚕']),
            ('puniOsusowake', ['Osusowake', 'Osusowake', 'Osusowake', 'Osusowake', 'おすそわけ', '나눠주기', 'Osusowake', 'Осусовакэ', '分享', '分享']),
        ]),
}

def mk(vals):
    return {'extractionState': 'manual', 'localizations': {l: {'stringUnit': {'state': 'translated', 'value': v}} for l, v in zip(L, vals)}}

d = json.loads(P.read_text(encoding='utf-8'))
S = d['strings']
for num, bd in BOSSES.items():
    S[f'enemy.boss.{num}'] = mk(bd['name'])
    S[f'editor.pattern.bosssection.{num}'] = mk([t.format(b=n) for t, n in zip(SECT, bd['name'])])
    if not bd.get('secret'):   # 覚醒が秘密のボス(ぷにまる)は、ショップの説明を作らない(ショップに出さない)
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
