# -*- coding: utf-8 -*-
"""竜王(1.4.0)の文言を、Localizable.xcstrings の10言語に書き込む。何度流しても同じ結果。
使い方: python3 tools/add_dragon_strings.py
並びは L と同じ(de, en, es, fr, ja, ko, pt-BR, ru, zh-Hans, zh-Hant)"""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent.parent / 'DanmakuApp/Localizable.xcstrings'
L = ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant']

NAME = ['Drachenkönig', 'Dragon King', 'Rey Dragón', 'Roi Dragon', '竜王', '용왕', 'Rei Dragão', 'Король драконов', '龙王', '龍王']
MOVES = [
    ('dragonBreath', ['Höllenfeuer-Brüllen', 'Hellfire Roar', 'Rugido infernal', 'Rugissement infernal', '劫火の咆哮', '겁화의 포효', 'Rugido infernal', 'Рёв адского пламени', '劫火咆哮', '劫火咆哮']),
    ('dragonRaid', ['Sturmangriff', 'Assault', 'Asalto', 'Assaut', '強襲', '강습', 'Investida', 'Натиск', '强袭', '強襲']),
    ('dragonGale', ['Sturmzone', 'Gale Zone', 'Zona de vendaval', 'Zone de tempête', '暴風圏', '폭풍권', 'Zona de vendaval', 'Зона бури', '暴风圈', '暴風圈']),
    ('dragonInhale', ['Sternenfresser', 'Star Eater', 'Devorador de estrellas', "Dévoreur d'étoiles", '星喰い', '별삼키기', 'Devorador de estrelas', 'Пожиратель звёзд', '噬星', '噬星']),
    ('dragonGlide', ['Glühender Gleitflug', 'Scorching Glide', 'Planeo abrasador', 'Vol plané brûlant', '灼熱の滑空', '작열의 활공', 'Planeio escaldante', 'Палящий полёт', '灼热滑翔', '灼熱滑翔']),
    ('dragonRoar', ['Drachenschrecken', "Dragon's Dread", 'Intimidación dracónica', 'Terreur draconique', '竜の威圧', '용의 위압', 'Intimidação dracônica', 'Драконий трепет', '龙之威压', '龍之威壓']),
    ('dragonQuake', ['Schlund des Abgrunds', 'Jaws of the Abyss', 'Fauces del abismo', "Mâchoires de l'abîme", '奈落の顎', '나락의 턱', 'Mandíbulas do abismo', 'Пасть бездны', '奈落之颚', '奈落之顎']),
    ('dragonTail', ['Schwanzhieb', 'Tail Strike', 'Coletazo', 'Coup de queue', '竜尾一閃', '용미일섬', 'Golpe de cauda', 'Удар хвоста', '龙尾一闪', '龍尾一閃']),
    ('dragonRampage', ['Purpurner Wirbel', 'Crimson Cyclone', 'Ciclón carmesí', 'Cyclone écarlate', '紅蓮の大旋回', '홍련의 대선회', 'Ciclone carmesim', 'Багровый вихрь', '红莲大回旋', '紅蓮大迴旋']),
    ('dragonEnd', ['Feuer von Megiddo', 'Fire of Megiddo', 'Fuego de Meguido', 'Feu de Megiddo', 'メギドの火', '메기도의 불', 'Fogo de Megido', 'Огонь Мегиддо', '米吉多之火', '米吉多之火']),
]
FORMS = [
    ['Normal', 'Normal', 'Normal', 'Normal', '通常', '통상', 'Normal', 'Обычный', '通常', '通常'],
    ['Azurflamme', 'Azure Flame', 'Llama azur', 'Flamme azur', '蒼炎', '창염', 'Chama azul', 'Лазурное пламя', '苍炎', '蒼炎'],
    ['Violetter Blitz', 'Violet Lightning', 'Rayo violeta', 'Éclair violet', '紫電', '자전', 'Raio violeta', 'Фиолетовая молния', '紫电', '紫電'],
    ['Platin', 'Platinum', 'Platino', 'Platine', '白金', '백금', 'Platina', 'Платина', '白金', '白金'],
]
TEXT = {
    'dragon.cutin.awaken': ['ERWACHEN · STUFE %d', 'AWAKENING · STAGE %d', 'DESPERTAR · NIVEL %d', 'ÉVEIL · NIVEAU %d', '覚醒 第%d段階', '각성 %d단계',
                            'DESPERTAR · NÍVEL %d', 'ПРОБУЖДЕНИЕ · СТУПЕНЬ %d', '觉醒 第%d阶段', '覺醒 第%d階段'],
    'dragon.cutin.normal': ['Normale Gestalt', 'Normal Form', 'Forma normal', 'Forme normale', '通常の姿', '통상 모습', 'Forma normal', 'Обычный облик', '通常形态', '通常形態'],
    'editor.dragon.forms': ['Gestalt je Phase', 'Form for each phase', 'Forma por fase', 'Forme par phase', '段階ごとの姿', '페이즈별 모습', 'Forma por fase', 'Облик в каждой фазе', '各阶段的形态', '各階段的形態'],
    'editor.dragon.forms.note': [
        'Wähle für jede Phase die Gestalt des Drachenkönigs. Beim Wechsel gibt es einen Effekt, und stärkere Gestalten machen dieselben Techniken heftiger (Normal → Azurflamme → Violetter Blitz → Platin).',
        "Choose the Dragon King's form for each phase. A cut-in plays when it changes, and stronger forms make the same moves fiercer (Normal → Azure Flame → Violet Lightning → Platinum).",
        'Elige la forma del Rey Dragón para cada fase. Al cambiar aparece un efecto, y las formas más fuertes hacen más feroces las mismas técnicas (Normal → Llama azur → Rayo violeta → Platino).',
        "Choisissez la forme du Roi Dragon pour chaque phase. Un effet s'affiche au changement, et les formes plus fortes rendent les mêmes techniques plus féroces (Normal → Flamme azur → Éclair violet → Platine).",
        '竜王は、段階ごとに姿を選べます。姿が変わる瞬間に演出が入り、強い姿ほど同じ技でも激しくなります(通常 → 蒼炎 → 紫電 → 白金の順に強い)。',
        '페이즈마다 용왕의 모습을 고를 수 있어요. 모습이 바뀔 때 연출이 나오고, 강한 모습일수록 같은 기술도 더 격렬해져요(통상 → 창염 → 자전 → 백금).',
        'Escolha a forma do Rei Dragão para cada fase. Um efeito aparece na troca, e formas mais fortes deixam os mesmos golpes mais ferozes (Normal → Chama azul → Raio violeta → Platina).',
        'Выберите облик Короля драконов для каждой фазы. При смене появляется эффект, а более сильный облик делает те же приёмы яростнее (Обычный → Лазурное пламя → Фиолетовая молния → Платина).',
        '可为每个阶段选择龙王的形态。切换时会有演出，形态越强，同样的招式也越猛烈（通常 → 苍炎 → 紫电 → 白金）。',
        '可為每個階段選擇龍王的形態。切換時會有演出，形態越強，同樣的招式也越猛烈（通常 → 蒼炎 → 紫電 → 白金）。'],
    'editor.dragon.interval.note': [
        'Der Drachenkönig setzt jeweils nur eine Technik ein (sein Körper bewegt sich). Läuft gerade eine andere, wartet er, bis sie endet. Das Intervall ist die kürzeste Zeit, bis dieselbe Technik wieder möglich ist.',
        'The Dragon King uses one move at a time (its body moves). If another move is in progress, it waits until that ends. The interval is the shortest time before the same move can be used again.',
        'El Rey Dragón usa una técnica a la vez (su cuerpo se mueve). Si hay otra en curso, espera a que termine. El intervalo es el tiempo mínimo hasta poder repetir la misma técnica.',
        "Le Roi Dragon utilise une technique à la fois (son corps se déplace). Si une autre est en cours, il attend qu'elle se termine. L'intervalle est le délai minimal avant de pouvoir réutiliser la même technique.",
        '竜王の技は1つずつ出ます(本体が動くため)。ほかの技の途中なら、終わるまで待ちます。間隔は、同じ技を次に出せるまでの最短の時間です。',
        '용왕의 기술은 한 번에 하나씩 나와요(몸이 움직이기 때문). 다른 기술이 진행 중이면 끝날 때까지 기다려요. 간격은 같은 기술을 다시 쓸 수 있을 때까지의 최소 시간이에요.',
        'O Rei Dragão usa um golpe por vez (o corpo se move). Se outro estiver em andamento, ele espera terminar. O intervalo é o tempo mínimo até poder usar o mesmo golpe de novo.',
        'Король драконов использует приёмы по одному (его тело движется). Если идёт другой приём, он ждёт его окончания. Интервал — минимальное время до повторного использования того же приёма.',
        '龙王一次只使用一个招式（因为本体会移动）。如果其他招式正在进行，会等到结束。间隔是同一招式再次使用前的最短时间。',
        '龍王一次只使用一個招式（因為本體會移動）。如果其他招式正在進行，會等到結束。間隔是同一招式再次使用前的最短時間。'],
    # 竜王はチケット3枚(サーバーの TICKET_COST と同じ)
    'shop.boss.ticket.cost': ['Für %1$lld Tickets eintauschbar (du hast %2$lld).', 'Exchange for %1$lld tickets (you have %2$lld).', 'Se canjea por %1$lld tickets (tienes %2$lld).',
                              'Échangeable contre %1$lld tickets (vous en avez %2$lld).', 'チケット%1$lld枚と交換できます(いま%2$lld枚)', '티켓 %1$lld장과 교환할 수 있어요 (지금 %2$lld장)',
                              'Troque por %1$lld tickets (você tem %2$lld).', 'Можно обменять на %1$lld билета (у вас %2$lld).', '可用%1$lld张券兑换(现有%2$lld张)', '可用%1$lld張券兌換(現有%2$lld張)'],
    'ticket.confirm.message.n': ['Dieser Boss kostet %lld Tickets. Das lässt sich nicht rückgängig machen.', 'This Boss costs %lld tickets. This can’t be undone.',
                                 'Este jefe cuesta %lld tickets. No se puede deshacer.', 'Ce boss coûte %lld tickets. C’est définitif.',
                                 'このボスは、チケット%lld枚と交換です。交換したあとは、取り消せません。', '이 보스는 티켓 %lld장과 교환해요. 교환 후에는 취소할 수 없어요.',
                                 'Este chefe custa %lld tickets. Não dá para desfazer.', 'Этот босс стоит %lld билета. Отменить нельзя.',
                                 '这个 Boss 需要%lld张券兑换。兑换后无法撤销。', '這個 Boss 需要%lld張券兌換。兌換後無法撤銷。'],
    'shop.boss.13.desc': ['Drachenkönig: 10 Techniken und 4 Gestalten', 'Dragon King — 10 moves and 4 forms', 'Rey Dragón: 10 técnicas y 4 formas', 'Roi Dragon : 10 techniques et 4 formes',
                          '竜王 ― 10の技と、4つの姿', '용왕 ― 기술 10개와 모습 4가지', 'Rei Dragão: 10 golpes e 4 formas', 'Король драконов: 10 приёмов и 4 облика', '龙王 ― 10种招式与4种形态', '龍王 ― 10種招式與4種形態'],
}
SECT = ['{b}: Techniken (nur mit diesem Aussehen)', '{b} moves (only with this look)', '{b}: técnicas (solo con este aspecto)', '{b} : techniques (uniquement avec cet aspect)',
        '{b}の技(この見た目のときだけ)', '{b}의 기술 (이 모습일 때만)', '{b}: golpes (só com este visual)', '{b}: приёмы (только с этим обликом)', '{b}的招式(仅限此外观)', '{b}的招式(僅限此外觀)']
JOINS = [(', ', ' und '), (', ', ' and '), (', ', ' y '), (', ', ' et '), ('・', None), (', ', None), (', ', ' e '), (', ', ' и '), ('、', None), ('、', None)]
TAILS = ['. Er fliegt über den Bildschirm, mit Flächenangriffen, Fesseln und einer Sofort-K.-o.-Technik. Wähle die Gestalt je Phase – stärkere Gestalten machen alle Techniken heftiger.',
         '. It flies around the screen, with area attacks, binding, and an instant-kill move. Choose its form for each phase — stronger forms make every move fiercer.',
         '. Vuela por la pantalla, con ataques de área, ataduras y una técnica de muerte instantánea. Elige su forma en cada fase: las más fuertes hacen más feroces todas las técnicas.',
         '. Il vole à travers l\'écran, avec attaques de zone, entraves et une technique mortelle instantanée. Choisissez sa forme à chaque phase : les plus fortes rendent toutes les techniques plus féroces.',
         '。本体が飛び回り、範囲攻撃・バインド・即死技も。段階ごとに姿を選べて、強い姿ほど技が激しくなります。',
         '. 화면을 날아다니며 범위 공격·속박·즉사기까지 써요. 페이즈마다 모습을 고를 수 있고, 강한 모습일수록 모든 기술이 격렬해져요.',
         '. Ele voa pela tela, com ataques em área, amarras e um golpe de morte instantânea. Escolha a forma em cada fase: formas mais fortes deixam todos os golpes mais ferozes.',
         '. Летает по экрану, с атаками по площади, сковыванием и мгновенно убивающим приёмом. Облик выбирается для каждой фазы — чем сильнее облик, тем яростнее приёмы.',
         '。本体会在画面中飞来飞去，还有范围攻击、束缚和即死技。可为每个阶段选择形态，形态越强招式越猛烈。',
         '。本體會在畫面中飛來飛去，還有範圍攻擊、束縛和即死技。可為每個階段選擇形態，形態越強招式越猛烈。']


def mk(vals):
    assert len(vals) == len(L)
    return {'extractionState': 'manual', 'localizations': {l: {'stringUnit': {'state': 'translated', 'value': v}} for l, v in zip(L, vals)}}


d = json.loads(P.read_text(encoding='utf-8'))
S = d['strings']
S['enemy.boss.13'] = mk(NAME)
S['editor.pattern.bosssection.13'] = mk([t.format(b=n) for t, n in zip(SECT, NAME)])
for key, names in MOVES:
    S[f'pattern.{key}'] = mk(names)
for i, f in enumerate(FORMS):
    S[f'dragon.form.{i}'] = mk(f)
for k, v in TEXT.items():
    S[k] = mk(v)
moves = []
for i in range(len(L)):
    ns = [m[1][i] for m in MOVES]
    sep, last = JOINS[i]
    moves.append(sep.join(ns[:-1]) + (last or sep) + ns[-1] + TAILS[i])
S['shop.boss.13.moves'] = mk(moves)
P.write_text(json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ': ')), encoding='utf-8')
print('ok')
