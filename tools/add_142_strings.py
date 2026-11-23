# -*- coding: utf-8 -*-
"""1.4.2: 弾幕パック3・弾の形「＝」・左右からの弾の高さ・段階なし・発射台のコピー/初期値に戻す の文言を足す。
使い方: python3 tools/add_142_strings.py
並びは L と同じ(de, en, es, fr, ja, ko, pt-BR, ru, zh-Hans, zh-Hant)。パターンの名前は、既存の名前とかぶらないか確かめる"""
import json, pathlib, sys
P = pathlib.Path(__file__).resolve().parent.parent / 'DanmakuApp/Localizable.xcstrings'
L = ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant']

NAMES = {
    'radialLaser': ['Rundumlaser', 'Omni Laser', 'Láser omnidireccional', 'Laser omnidirectionnel', '全方位レーザー', '전방위 레이저', 'Laser em todas as direções', 'Круговой лазер', '全方位激光', '全方位雷射'],
    'lightning': ['Blitzschlag', 'Lightning Strike', 'Relámpago', 'Foudre', '落雷', '낙뢰', 'Relâmpago', 'Удар молнии', '落雷', '落雷'],
    'carpetBomb': ['Bombenteppich', 'Carpet Bomb', 'Bombardeo en línea', 'Tapis de bombes', '爆撃ライン', '폭격 라인', 'Bombardeio em linha', 'Ковровая бомбардировка', '轰炸线', '轟炸線'],
    'dashShot': ['Sprintschuss', 'Dash Shot', 'Disparo acelerón', 'Tir éclair', '急加速弾', '급가속탄', 'Tiro arrancada', 'Рывковый выстрел', '急加速弹', '急加速彈'],
    'implode': ['Implosion', 'Implosion', 'Implosión', 'Implosion', '吸い込み弾', '흡입탄', 'Implosão', 'Схлопывание', '吸入弹', '吸入彈'],
    'pincer': ['Zangenangriff', 'Pincer Attack', 'Ataque en pinza', 'Prise en tenaille', '挟み撃ち', '협공', 'Ataque em pinça', 'Клещи', '夹击', '夾擊'],
    'whirlwind': ['Wirbelwind', 'Whirlwind', 'Torbellino giratorio', 'Tourbillon de balles', 'つむじ風', '회오리바람', 'Rodamoinho de balas', 'Вихрь', '旋风团', '旋風團'],
    'bounceBall': ['Springball', 'Bouncing Ball', 'Pelota saltarina', 'Balle rebondissante', 'バウンドボール', '바운드 볼', 'Bola quicante', 'Прыгучий мяч', '弹跳球', '彈跳球'],
    'needle': ['Nadeln', 'Needles', 'Agujas', 'Aiguilles', 'ニードル', '니들', 'Agulhas', 'Иглы', '飞针', '飛針'],
    'trackLaser': ['Zielverfolgungslaser', 'Tracking Laser', 'Láser rastreador', 'Laser traqueur', '追跡レーザー', '추적 레이저', 'Laser rastreador', 'Следящий лазер', '追踪激光', '追蹤雷射'],
    'blinkShot': ['Teleportschuss', 'Blink Shot', 'Disparo teletransporte', 'Tir téléporté', '瞬間移動弾', '순간이동탄', 'Tiro teleporte', 'Телепорт-выстрел', '瞬移弹', '瞬移彈'],
}
DESCS = {
    'radialLaser': ['Laserstrahlen in alle Richtungen, die sich beim Feuern langsam drehen.', 'Beams fire in every direction and slowly turn while firing.', 'Rayos en todas direcciones que giran despacio mientras disparan.', 'Des rayons dans toutes les directions, qui tournent lentement pendant le tir.', '全方向に光線を撃つ。撃っている間、ゆっくり回る。', '모든 방향으로 광선을 쏜다. 쏘는 동안 천천히 돈다.', 'Raios em todas as direções que giram devagar enquanto disparam.', 'Лучи во все стороны, которые медленно поворачиваются во время выстрела.', '向四面八方发射激光，发射时缓缓旋转。', '向四面八方發射雷射，發射時緩緩旋轉。'],
    'lightning': ['Blitze schlagen an zufälligen Stellen von oben ein.', 'Bolts strike straight down from the top at random spots.', 'Rayos caen desde arriba en lugares al azar.', "Des éclairs tombent du haut de l'écran à des endroits aléatoires.", '画面の上から、ばらばらの場所に縦の雷が落ちる。', '화면 위에서 무작위 위치로 세로 번개가 떨어진다.', 'Raios caem do alto em lugares aleatórios.', 'Молнии бьют сверху в случайных местах.', '雷电从画面上方随机落下。', '雷電從畫面上方隨機落下。'],
    'carpetBomb': ['Eine Kette von Explosionen rollt auf dich zu.', 'A chain of explosions rolls toward you, one after another.', 'Una cadena de explosiones avanza hacia ti, una tras otra.', "Une chaîne d'explosions avance vers vous, l'une après l'autre.", '自機へ向かって、爆発が順に連なる。', '자기를 향해 폭발이 차례로 이어진다.', 'Uma sequência de explosões avança até você, uma após a outra.', 'Цепочка взрывов катится к вам один за другим.', '爆炸朝自机方向依次连成一串。', '爆炸朝自機方向依序連成一串。'],
    'dashShot': ['Kriecht langsam und schießt plötzlich mit vierfacher Geschwindigkeit los.', 'Crawls out slowly, then suddenly dashes at four times the speed.', 'Sale despacio y de pronto acelera a cuatro veces la velocidad.', "Part lentement, puis fonce soudain quatre fois plus vite.", 'のろのろ進み、急にビュンと4倍の速さになる。', '느릿느릿 나아가다 갑자기 4배 속도로 튀어 나간다.', 'Sai devagar e de repente dispara a quatro vezes a velocidade.', 'Медленно ползёт, а потом резко ускоряется в четыре раза.', '慢吞吞前进，突然以4倍速度冲出。', '慢吞吞前進，突然以4倍速度衝出。'],
    'implode': ['Kugeln aus einem großen Ring rasen zur Mitte und fliegen hindurch.', 'Bullets rush in from a wide ring, cross the center and spread out again.', 'Las balas llegan desde un gran anillo, cruzan el centro y se dispersan.', "Les balles arrivent d'un grand anneau, traversent le centre et se dispersent.", '大きな輪から中心へ集まり、そのまま抜けて広がる。', '큰 원에서 중심으로 모였다가 그대로 빠져나가 퍼진다.', 'Os tiros vêm de um grande anel, cruzam o centro e se espalham.', 'Пули летят из большого кольца к центру и разлетаются дальше.', '弹幕从大圆圈向中心聚拢，穿过后再散开。', '彈幕從大圓圈向中心聚攏，穿過後再散開。'],
    'pincer': ['Kugeln kommen gleichzeitig von links und rechts auf deiner Höhe.', 'Shots come from both sides of the screen at your height at once.', 'Disparos desde ambos lados de la pantalla a tu altura a la vez.', "Des tirs arrivent des deux côtés de l'écran à votre hauteur.", '画面の左右から、自機の高さへ同時に飛んでくる。', '화면 좌우에서 자기 높이로 동시에 날아온다.', 'Tiros vêm dos dois lados da tela na sua altura ao mesmo tempo.', 'Пули летят одновременно слева и справа на вашей высоте.', '从画面左右两侧同时朝自机高度飞来。', '從畫面左右兩側同時朝自機高度飛來。'],
    'whirlwind': ['Ein kreisender Kugelknäuel treibt auf dich zu.', 'A spinning cluster of bullets drifts toward you.', 'Un grupo de balas girando se desliza hacia ti.', 'Un amas de balles en rotation dérive vers vous.', '回る弾のかたまりが、自機のほうへ流れてくる。', '도는 탄 덩어리가 자기 쪽으로 흘러온다.', 'Um grupo de tiros girando vem flutuando até você.', 'Вращающийся сгусток пуль плывёт к вам.', '旋转的弹幕团朝自机飘来。', '旋轉的彈幕團朝自機飄來。'],
    'bounceBall': ['Wird hochgeworfen, fällt im Bogen und springt einmal vom Boden ab.', 'Tossed up, falls in an arc and bounces once off the bottom.', 'Lanzada hacia arriba, cae en arco y rebota una vez en el suelo.', 'Lancée en l’air, retombe en arc et rebondit une fois en bas.', '上へ投げ上げ、放物線で落ちて、画面の下で1回はねる。', '위로 던져 포물선으로 떨어지고, 화면 아래에서 한 번 튀어 오른다.', 'Lançada para cima, cai em arco e quica uma vez no chão.', 'Подбрасывается, падает по дуге и один раз отскакивает от низа.', '向上抛起，沿抛物线落下，在画面底部弹一次。', '向上拋起，沿拋物線落下，在畫面底部彈一次。'],
    'needle': ['Lange, dünne Nadeln im Fächer.', 'A fan of long, thin needles.', 'Un abanico de agujas largas y finas.', 'Un éventail de longues aiguilles fines.', '細長い針の形の弾を、扇状に撃つ。', '가늘고 긴 바늘 모양의 탄을 부채꼴로 쏜다.', 'Um leque de agulhas longas e finas.', 'Веер длинных тонких игл.', '呈扇形射出细长的飞针。', '呈扇形射出細長的飛針。'],
    'trackLaser': ['Folgt dir beim Aufladen, stoppt und feuert dann.', 'Follows you while charging, then locks and fires.', 'Te sigue mientras carga, se fija y dispara.', 'Vous suit pendant la charge, se fige puis tire.', 'ためる間に自機を追い、止まってから撃つ。', '모으는 동안 자기를 따라오다가 멈춘 뒤 쏜다.', 'Segue você enquanto carrega, trava e dispara.', 'Следит за вами во время зарядки, затем замирает и стреляет.', '蓄力时追踪自机，锁定后发射。', '蓄力時追蹤自機，鎖定後發射。'],
    'blinkShot': ['Verschwindet im Flug kurz und taucht weiter vorne wieder auf.', 'Vanishes mid-flight and reappears further ahead.', 'Desaparece en pleno vuelo y reaparece más adelante.', 'Disparaît en plein vol et réapparaît plus loin.', '進みながら、ふっと消えて先に現れる。', '나아가다가 훅 사라져서 앞쪽에 나타난다.', 'Some no meio do voo e reaparece mais à frente.', 'Исчезает в полёте и появляется дальше впереди.', '飞行中忽然消失，在前方再出现。', '飛行中忽然消失，在前方再出現。'],
}
S = {
    'shop.pattern3.footer': ['Laser, Explosionen und Kugeln mit überraschenden Bewegungen. Level mit diesen Mustern kann jeder spielen, auch ohne Kauf.',
                             'Lasers, explosions and bullets with surprising moves. Anyone can play stages that use them, even without buying.',
                             'Láseres, explosiones y balas con movimientos sorprendentes. Cualquiera puede jugar los niveles que los usan, aunque no los compre.',
                             'Lasers, explosions et balles aux mouvements surprenants. Tout le monde peut jouer les niveaux qui les utilisent, même sans les acheter.',
                             'レーザー・爆発・意外な動きの弾幕です。使ったステージは、買っていない人も遊べます。',
                             '레이저·폭발·의외의 움직임을 가진 탄막입니다. 사용한 스테이지는 구매하지 않은 사람도 플레이할 수 있어요.',
                             'Lasers, explosões e tiros com movimentos surpreendentes. Qualquer pessoa pode jogar fases que os usam, mesmo sem comprar.',
                             'Лазеры, взрывы и пули с неожиданными движениями. Уровни с ними могут проходить все, даже без покупки.',
                             '激光、爆炸和动作出人意料的弹幕。使用它们的关卡，没购买的人也能玩。',
                             '雷射、爆炸和動作出人意料的彈幕。使用它們的關卡，沒購買的人也能玩。'],
    'editor.shape.equals': ['＝', '＝', '＝', '＝', '＝', '＝', '＝', '＝', '＝', '＝'],
    'editor.shape.bar': ['Stab', 'Bar', 'Barra', 'Barre', '棒', '막대', 'Barra', 'Палочка', '棒状', '棒狀'],
    'editor.height.label': ['Höhe', 'Height', 'Altura', 'Hauteur', '出る高さ', '나오는 높이', 'Altura', 'Высота', '出现高度', '出現高度'],
    'editor.height.standard': ['Standard', 'Standard', 'Normal', 'Standard', '標準', '표준', 'Padrão', 'Обычная', '标准', '標準'],
    'editor.height.full': ['Ganzer Bildschirm', 'Whole screen', 'Toda la pantalla', "Tout l'écran", '画面全体', '화면 전체', 'Tela inteira', 'Весь экран', '整个画面', '整個畫面'],
    'editor.height.lower': ['Untere Hälfte', 'Lower half', 'Mitad inferior', 'Moitié basse', '下半分', '아래 절반', 'Metade de baixo', 'Нижняя половина', '下半部', '下半部'],
    'editor.phases.count.none': ['Keine', 'None', 'Ninguna', 'Aucune', 'なし', '없음', 'Nenhuma', 'Нет', '无', '無'],
    'editor.phases.note.none': ['Keine Phasen: Der Boss ist mit einem Sieg besiegt.', 'No phases: beat the boss once and you win.', 'Sin fases: vence al jefe una vez y ganas.', 'Sans phases : battez le boss une fois et vous gagnez.', '段階なし: ボスを1回倒せば終わりです。', '단계 없음: 보스를 한 번 쓰러뜨리면 끝납니다.', 'Sem fases: derrote o chefe uma vez e você vence.', 'Без фаз: победите босса один раз — и всё.', '无阶段：打倒一次首领即结束。', '無階段：打倒一次頭目即結束。'],
    'editor.phases.note.none.time': ['Keine Phasen: Der Boss wechselt bis zum Zeitlimit nicht.', 'No phases: the boss stays the same until time runs out.', 'Sin fases: el jefe no cambia hasta que se acabe el tiempo.', "Sans phases : le boss ne change pas jusqu'à la fin du temps.", '段階なし: 制限時間まで、段階は変わりません。', '단계 없음: 제한 시간까지 단계가 바뀌지 않습니다.', 'Sem fases: o chefe não muda até o tempo acabar.', 'Без фаз: босс не меняется до конца времени.', '无阶段：到时间结束前阶段不变。', '無階段：到時間結束前階段不變。'],
    'editor.copy': ['Kopieren', 'Copy', 'Copiar', 'Copier', 'コピー', '복사', 'Copiar', 'Копировать', '复制', '複製'],
    'editor.paste': ['%@ einfügen', 'Paste %@', 'Pegar %@', 'Coller %@', '%@ を貼り付け', '%@ 붙여넣기', 'Colar %@', 'Вставить: %@', '粘贴 %@', '貼上 %@'],
    'editor.emitter.menu': ['Mehr', 'More', 'Más', 'Plus', 'その他', '더 보기', 'Mais', 'Ещё', '更多', '更多'],
    'editor.reset.all': ['Auf Standard zurücksetzen', 'Reset to defaults', 'Restablecer', 'Réinitialiser', '初期値に戻す', '초기값으로 되돌리기', 'Restaurar padrão', 'Сбросить', '恢复默认', '恢復預設'],
    'editor.reset.one': ['Zurück', 'Reset', 'Restablecer', 'Rétablir', '戻す', '되돌리기', 'Restaurar', 'Сброс', '还原', '還原'],
    'editor.reset.title': ['Auf Standard zurücksetzen?', 'Reset to defaults?', '¿Restablecer?', 'Réinitialiser ?', '初期値に戻しますか?', '초기값으로 되돌릴까요?', 'Restaurar o padrão?', 'Сбросить?', '要恢复默认吗？', '要恢復預設嗎？'],
    'editor.reset.message': ['Intervall, Anzahl, Tempo, Winkel, Richtung, Farbe, Form, Zielen, Spiegeln und Höhe werden auf Standard gesetzt. Muster, Position und Zeit bleiben.',
                             'Interval, count, speed, angle, direction, color, shape, aiming, mirroring and height go back to defaults. The pattern, position and timing stay.',
                             'El intervalo, la cantidad, la velocidad, el ángulo, la dirección, el color, la forma, la puntería, el reflejo y la altura vuelven a los valores iniciales. Se mantienen el patrón, la posición y el tiempo.',
                             "L'intervalle, le nombre, la vitesse, l'angle, la direction, la couleur, la forme, la visée, le miroir et la hauteur reviennent aux valeurs par défaut. Le motif, la position et le timing restent.",
                             '間隔・数・速さ・角度・向き・色・弾の形・狙い方・左右反転・出る高さを初期値に戻します。パターン・位置・時間はそのままです。',
                             '간격·개수·속도·각도·방향·색·탄 모양·조준·좌우 반전·나오는 높이를 초기값으로 되돌립니다. 패턴·위치·시간은 그대로입니다.',
                             'Intervalo, quantidade, velocidade, ângulo, direção, cor, forma, mira, espelhamento e altura voltam ao padrão. O padrão, a posição e o tempo ficam.',
                             'Интервал, количество, скорость, угол, направление, цвет, форма, прицел, отражение и высота вернутся к исходным. Узор, позиция и время сохранятся.',
                             '间隔、数量、速度、角度、朝向、颜色、弹形、瞄准方式、左右翻转、出现高度将恢复默认。图案、位置和时间保持不变。',
                             '間隔、數量、速度、角度、朝向、顏色、彈形、瞄準方式、左右翻轉、出現高度將恢復預設。圖案、位置和時間保持不變。'],
    'editor.reset.do': ['Zurücksetzen', 'Reset', 'Restablecer', 'Réinitialiser', '戻す', '되돌리기', 'Restaurar', 'Сбросить', '恢复', '恢復'],
}
for k, v in NAMES.items(): S['pattern.' + k] = v
# パック3の題は、パック2の題の「2」を「3」にしたもの(下で作る)
for k, v in DESCS.items(): S['shop.pattern.' + k] = v

d = json.loads(P.read_text(encoding='utf-8'))
# 既存のパターンの名前とかぶらないか(言語ごと)
existing = {}
for key, val in d['strings'].items():
    if key.startswith('pattern.') and key.count('.') == 1 and key[8:] not in NAMES:
        for l, u in val.get('localizations', {}).items():
            existing.setdefault(l, set()).add(u['stringUnit']['value'])
bad = [(k, l, v) for k, vals in NAMES.items() for l, v in zip(L, vals) if v in existing.get(l, set())]
if bad:
    print('名前がかぶっています:', bad); sys.exit(1)
for k2, k3 in [('shop.pattern2.title', 'shop.pattern3.title'), ('shop.pattern2.pack', 'shop.pattern3.pack'), ('editor.pattern.pack2section', 'editor.pattern.pack3section')]:
    S[k3] = [d['strings'][k2]['localizations'][l]['stringUnit']['value'].replace('2', '3') for l in L]
for k, vals in S.items():
    assert len(vals) == len(L), k
    d['strings'][k] = {'extractionState': 'manual', 'localizations': {l: {'stringUnit': {'state': 'translated', 'value': v}} for l, v in zip(L, vals)}}
P.write_text(json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ': ')), encoding='utf-8')
print('ok', len(S))
