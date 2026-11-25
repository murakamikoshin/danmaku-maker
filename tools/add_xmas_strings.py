# -*- coding: utf-8 -*-
"""期間限定のボス(1.5.0)の売り場まわりの文言を、Localizable.xcstrings の10言語に書き込む。何度流しても同じ結果。
使い方: python3 tools/add_xmas_strings.py
並びは L と同じ(de, en, es, fr, ja, ko, pt-BR, ru, zh-Hans, zh-Hant)
ボスの名前・技の名前(enemy.boss.14 など)は、絵と技が決まってから足す"""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent.parent / 'DanmakuApp/Localizable.xcstrings'
L = ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant']

TEXT = {
    # ---- クリスマスの BGM(番号 7。ノエルを持っている人が選べる)
    'bgm.7': ['Weihnachten', 'Christmas', 'Navidad', 'Noël', 'クリスマス', '크리스마스', 'Natal', 'Рождество', '圣诞', '聖誕'],
    'bgm.7.sub': [
        'Noels Lied. Sanft wie eine Spieluhr', "Noel's tune. Gentle, like a music box", 'La canción de Noel. Suave, como una caja de música',
        'L’air de Noël. Doux comme une boîte à musique', 'ノエルの曲。オルゴールのようにやさしい', '노엘의 곡. 오르골처럼 부드러워요',
        'A música da Noel. Suave como uma caixinha de música', 'Мелодия Ноэль. Нежная, как музыкальная шкатулка', '诺艾尔的曲子。像八音盒一样温柔', '諾艾爾的曲子。像音樂盒一樣溫柔',
    ],
    'editor.bgm.santa.locked': [
        'Dieses Lied kann nur wählen, wer Noel besitzt. Anhören kann es jeder, und Spieler brauchen Noel nicht.',
        'Only players who own Noel can choose this tune. Anyone can preview it, and players do not need Noel to hear it.',
        'Solo quienes tienen a Noel pueden elegir esta canción. Cualquiera puede escucharla, y quienes juegan no necesitan a Noel.',
        'Seuls ceux qui possèdent Noël peuvent choisir cet air. Tout le monde peut l’écouter, et les joueurs n’ont pas besoin de Noël.',
        'ノエルを持っている人だけが選べる曲です。試聴はだれでもでき、遊ぶ人はノエルを持っていなくてもこの曲で遊べます。',
        '노엘을 보유한 사람만 선택할 수 있는 곡이에요. 미리 듣기는 누구나 할 수 있고, 플레이하는 사람은 노엘이 없어도 이 곡으로 플레이할 수 있어요.',
        'Só quem tem a Noel pode escolher esta música. Qualquer um pode ouvir, e quem joga não precisa ter a Noel.',
        'Выбрать эту мелодию могут только владельцы Ноэль. Прослушать может каждый, а игрокам Ноэль не нужна.',
        '只有拥有诺艾尔的人才能选择这首曲子。任何人都可以试听,游玩者无需拥有诺艾尔。',
        '只有擁有諾艾爾的人才能選擇這首曲子。任何人都可以試聽,遊玩者無需擁有諾艾爾。',
    ],
    'publish.boss.bgm.santa': [
        'Als BGM ist Noels Lied gewählt.', "Noel's tune is selected as the BGM.", 'Has elegido la canción de Noel como BGM.', 'L’air de Noël est choisi comme BGM.',
        'BGMにノエルの曲(クリスマス)を選んでいます。', 'BGM으로 노엘의 곡(크리스마스)을 선택했어요.', 'A música da Noel está escolhida como BGM.', 'В качестве BGM выбрана мелодия Ноэль.',
        'BGM选择了诺艾尔的曲子(圣诞)。', 'BGM選擇了諾艾爾的曲子(聖誕)。',
    ],
    'shop.boss.santa.bgm': [
        'Bonus: ein Weihnachtslied als Stage-BGM', 'Bonus: a Christmas tune for your stage BGM', 'Extra: una canción navideña para el BGM de tus niveles',
        'Bonus : un air de Noël pour le BGM de vos niveaux', 'おまけ: ステージのBGMにクリスマスの曲', '덤: 스테이지 BGM으로 크리스마스 곡',
        'Bônus: uma música de Natal para o BGM das suas fases', 'Бонус: рождественская мелодия для BGM уровня', '附赠:可用作关卡BGM的圣诞曲', '附贈:可用作關卡BGM的聖誕曲',
    ],
    # ---- ボス「クリスマス娘 ノエル」(番号 14)と、技の名前
    'enemy.boss.14': ['Noel', 'Noel', 'Noel', 'Noël', 'ノエル', '노엘', 'Noel', 'Ноэль', '诺艾尔', '諾艾爾'],
    'editor.pattern.bosssection.14': [
        'Noel: Techniken (nur mit diesem Aussehen)', 'Noel moves (only with this look)', 'Noel: técnicas (solo con este aspecto)',
        'Noël : techniques (uniquement avec cet aspect)', 'ノエルの技(この見た目のときだけ)', '노엘의 기술 (이 모습일 때만)',
        'Noel: golpes (só com este visual)', 'Ноэль: приёмы (только с этим обликом)', '诺艾尔的招式(仅限此外观)', '諾艾爾的招式(僅限此外觀)',
    ],
    'shop.boss.14.desc': [
        'Weihnachtsmädchen Noel: 5 Techniken und Erwachen', 'Noel the Christmas Girl — 5 moves, and she awakens', 'Noel, la chica navideña: 5 técnicas y despertar',
        'Noël, la fille de Noël : 5 techniques et éveil', 'クリスマス娘 ノエル ― 5つの技と、覚醒', '크리스마스 소녀 노엘 ― 기술 5개와 각성',
        'Noel, a garota do Natal: 5 golpes e despertar', 'Рождественская девочка Ноэль: 5 приёмов и пробуждение', '圣诞少女 诺艾尔 ― 5种招式与觉醒', '聖誕少女 諾艾爾 ― 5種招式與覺醒',
    ],
    'shop.boss.14.moves': [
        'Öffne dich, Geschenk · Jingle-Ring · Zuckerstange · Baumlichter · Mitternachtslieferung. Nach dem Erwachen wird sie zum schwarzen Weihnachtsmädchen und die Techniken werden stärker. Wann sie erwacht, bestimmst du.',
        'Open Up, Present · Jingle Ring · Candy Cane · Tree Lights · Midnight Delivery. When she awakens she turns into Black Santa and her moves get stronger, and you choose when she awakens.',
        'Ábrete, regalo · Anillo de cascabeles · Bastón de caramelo · Luces del árbol · Entrega de medianoche. Al despertar se vuelve Santa negra y sus técnicas se fortalecen. Tú decides cuándo despierta.',
        'Ouvre-toi, cadeau · Anneau de grelots · Sucre d’orge · Lumières du sapin · Livraison de minuit. À l’éveil, elle devient la Mère Noël noire et ses techniques se renforcent. Vous choisissez quand elle s’éveille.',
        'ひらけ、プレゼント・ジングル・リング・キャンディケイン・ツリーの灯・真夜中の配達。覚醒すると黒サンタになって技が強くなり、覚醒する段階は自分で決められます。',
        '열려라, 선물 · 징글 링 · 캔디 케인 · 트리의 불빛 · 한밤중의 배달. 각성하면 블랙 산타가 되어 기술이 강해지고, 각성하는 단계는 직접 정할 수 있어요.',
        'Abra-se, presente · Anel de guizos · Bengala doce · Luzes da árvore · Entrega da meia-noite. Ao despertar, ela vira a Noel negra e os golpes ficam mais fortes. Você escolhe quando ela desperta.',
        'Откройся, подарок · Кольцо бубенцов · Карамельная трость · Огни ёлки · Полуночная доставка. После пробуждения она становится Чёрной Сантой, а приёмы усиливаются. Когда она пробудится — решаете вы.',
        '打开吧,礼物、铃儿响环、拐杖糖、圣诞树之灯、午夜配送。觉醒后变为黑圣诞少女,招式更强,觉醒的阶段可自行决定。',
        '打開吧,禮物、鈴兒響環、拐杖糖、聖誕樹之燈、午夜配送。覺醒後變為黑聖誕少女,招式更強,覺醒的階段可自行決定。',
    ],
    'pattern.santaGift': ['Öffne dich, Geschenk', 'Open Up, Present', 'Ábrete, regalo', 'Ouvre-toi, cadeau', 'ひらけ、プレゼント', '열려라, 선물', 'Abra-se, presente', 'Откройся, подарок', '打开吧,礼物', '打開吧,禮物'],
    'pattern.santaBell': ['Jingle-Ring', 'Jingle Ring', 'Anillo de cascabeles', 'Anneau de grelots', 'ジングル・リング', '징글 링', 'Anel de guizos', 'Кольцо бубенцов', '铃儿响环', '鈴兒響環'],
    'pattern.santaCane': ['Zuckerstange', 'Candy Cane', 'Bastón de caramelo', 'Sucre d’orge', 'キャンディケイン', '캔디 케인', 'Bengala doce', 'Карамельная трость', '拐杖糖', '拐杖糖'],
    'pattern.santaTree': ['Baumlichter', 'Tree Lights', 'Luces del árbol', 'Lumières du sapin', 'ツリーの灯', '트리의 불빛', 'Luzes da árvore', 'Огни ёлки', '圣诞树之灯', '聖誕樹之燈'],
    'pattern.santaDelivery': ['Mitternachtslieferung', 'Midnight Delivery', 'Entrega de medianoche', 'Livraison de minuit', '真夜中の配達', '한밤중의 배달', 'Entrega da meia-noite', 'Полуночная доставка', '午夜配送', '午夜配送'],
    # ---- クリスマスのテーマと自機
    'theme.xmas': ['Weihnachten', 'Christmas', 'Navidad', 'Noël', 'クリスマス', '크리스마스', 'Natal', 'Рождество', '圣诞', '聖誕'],
    'ship.sleigh_xmas': ['Schlitten', 'Sleigh', 'Trineo', 'Traîneau', 'そり', '썰매', 'Trenó', 'Сани', '雪橇', '雪橇'],
    'ship.reindeer_xmas': ['Rentier', 'Reindeer', 'Reno', 'Renne', 'トナカイ', '순록', 'Rena', 'Олень', '驯鹿', '馴鹿'],
    'ship.snowflake_xmas': ['Schneeflocke', 'Snowflake', 'Copo de nieve', 'Flocon', '雪の結晶', '눈꽃', 'Floco de neve', 'Снежинка', '雪花', '雪花'],
    'shop.ships.title': [
        'Weihnachtsschiffe', 'Christmas Ships', 'Naves navideñas', 'Vaisseaux de Noël', 'クリスマスの自機',
        '크리스마스 기체', 'Naves de Natal', 'Рождественские корабли', '圣诞自机', '聖誕自機',
    ],
    'shop.ships.footer': [
        'Nur das Aussehen ändert sich; die Trefferzone bleibt gleich. Nur im Verkaufszeitraum erhältlich, danach für immer nutzbar.',
        'Looks only; the hit area stays the same. Only sold during the sale period, then yours forever.',
        'Solo cambia el aspecto; la zona de impacto es la misma. Solo se vende durante el periodo de venta y luego es tuya para siempre.',
        'Apparence uniquement ; la zone de collision reste la même. En vente uniquement pendant la période, puis à vous pour toujours.',
        '変わるのは見た目だけで、当たり判定は同じです。買えるのは期間中だけ。買ったあとは、ずっと使えます。',
        '바뀌는 것은 겉모습뿐이고 피격 판정은 같아요. 기간 중에만 구매할 수 있고, 구매한 뒤에는 계속 사용할 수 있어요.',
        'Só muda a aparência; a área de colisão é a mesma. Só é vendido durante o período de venda e depois é seu para sempre.',
        'Меняется только внешний вид; зона попадания та же. Продаётся только в период продажи, после покупки остаётся навсегда.',
        '仅改变外观,判定范围不变。仅在销售期内可购买,购买后可一直使用。',
        '僅改變外觀,判定範圍不變。僅在販售期內可購買,購買後可一直使用。',
    ],
    'shop.pack.theme': [
        'Thema „%@“', 'Theme "%@"', 'Tema «%@»', 'Thème « %@ »', 'テーマ「%@」', '테마 "%@"', 'Tema "%@"', 'Тема «%@»', '主题“%@”', '主題「%@」',
    ],
    # ---- 雑魚の見た目のセット(クリスマス)と、クリスマスパック
    'enemy.mook.5': ['Schneemann', 'Snowman', 'Muñeco de nieve', 'Bonhomme de neige', '雪だるま', '눈사람', 'Boneco de neve', 'Снеговик', '雪人', '雪人'],
    'enemy.mook.6': ['Geschenk', 'Gift box', 'Regalo', 'Cadeau', 'プレゼント箱', '선물 상자', 'Presente', 'Подарок', '礼物盒', '禮物盒'],
    'enemy.mook.7': ['Lebkuchen', 'Gingerbread', 'Jengibre', 'Pain d’épices', 'ジンジャーマン', '진저맨', 'Biscoito', 'Пряник', '姜饼人', '薑餅人'],
    'enemy.mook.8': ['Glöckchen', 'Bell', 'Campana', 'Clochette', '鈴', '방울', 'Sino', 'Колокольчик', '铃铛', '鈴鐺'],
    'shop.mooks.xmas.title': [
        'Weihnachts-Minions', 'Christmas Minions', 'Esbirros navideños', 'Sbires de Noël', 'クリスマスの雑魚セット',
        '크리스마스 졸개 세트', 'Lacaios de Natal', 'Рождественские миньоны', '圣诞小怪套装', '聖誕小怪套裝',
    ],
    'shop.mooks.xmas.desc': [
        '4 weihnachtliche Looks für die Minions in deinen Stages',
        '4 Christmas looks for the minions in your stages',
        '4 aspectos navideños para los esbirros de tus niveles',
        '4 apparences de Noël pour les sbires de vos niveaux',
        'ステージの雑魚を、クリスマスの見た目4種に',
        '스테이지의 졸개를 크리스마스 모습 4종으로',
        '4 visuais de Natal para os lacaios das suas fases',
        '4 рождественских облика для миньонов в ваших уровнях',
        '为关卡中的小怪换上4种圣诞造型',
        '為關卡中的小怪換上4種聖誕造型',
    ],
    'shop.mooks.footer': [
        'Nur das Aussehen ändert sich. Jeder kann Stages damit spielen; zum Veröffentlichen brauchst du das Set.',
        'Looks only. Anyone can play stages that use them; you need the set to publish one.',
        'Solo cambia el aspecto. Cualquiera puede jugar niveles que los usen; necesitas el set para publicar.',
        'Apparence uniquement. Tout le monde peut jouer aux niveaux qui les utilisent ; il faut le set pour publier.',
        '変わるのは見た目だけです。使っているステージは誰でも遊べます。公開するには、このセットが必要です。',
        '바뀌는 것은 겉모습뿐이에요. 사용한 스테이지는 누구나 플레이할 수 있고, 공개하려면 이 세트가 필요해요.',
        'Só muda a aparência. Qualquer um pode jogar fases que os usem; você precisa do conjunto para publicar.',
        'Меняется только внешний вид. Играть в такие уровни может каждый; для публикации нужен набор.',
        '仅改变外观。任何人都能游玩使用它们的关卡;发布关卡需要拥有此套装。',
        '僅改變外觀。任何人都能遊玩使用它們的關卡;發布關卡需要擁有此套裝。',
    ],
    'shop.mooks.seasonal.note': [
        'Nur im Verkaufszeitraum erhältlich. Einmal gekauft, bleibt das Set für immer nutzbar. Auch im Lifetime-Paket enthalten.',
        'Only sold during the sale period. Once bought, it is yours to use forever. Also included in the Lifetime Pack.',
        'Solo se vende durante el periodo de venta. Una vez comprado, podrás usarlo para siempre. También incluido en el Pack vitalicio.',
        'En vente uniquement pendant la période. Une fois acheté, il reste utilisable pour toujours. Aussi inclus dans le Pack à vie.',
        '買えるのは期間中だけです。買ったあとは、期間が終わってもずっと使えます。永久買い切りパックにも入っています。',
        '기간 중에만 구매할 수 있어요. 구매한 뒤에는 기간이 끝나도 계속 사용할 수 있어요. 영구 구매 팩에도 포함되어 있어요.',
        'Só é vendido durante o período de venda. Depois de comprar, é seu para usar para sempre. Também incluído no Pacote vitalício.',
        'Продаётся только в период продажи. После покупки остаётся у вас навсегда. Также входит в пожизненный набор.',
        '仅在销售期内可购买。购买后,即使销售期结束也能一直使用。永久买断包也包含此套装。',
        '僅在販售期內可購買。購買後,即使販售期結束也能一直使用。永久買斷包也包含此套裝。',
    ],
    'shop.pack.xmas.title': [
        'Weihnachtspaket', 'Christmas Pack', 'Pack de Navidad', 'Pack de Noël', 'クリスマスパック',
        '크리스마스 팩', 'Pacote de Natal', 'Рождественский набор', '圣诞礼包', '聖誕禮包',
    ],
    'shop.pack.xmas.desc': [
        'Alles zu Weihnachten in einem Paket – günstiger als einzeln',
        'Everything Christmas in one pack – cheaper than buying separately',
        'Todo lo navideño en un solo pack: más barato que por separado',
        'Tout Noël en un seul pack : moins cher que séparément',
        'クリスマス限定をまとめて。単品でそろえるよりお得',
        '크리스마스 한정을 한꺼번에. 따로 사는 것보다 저렴해요',
        'Tudo de Natal em um pacote: mais barato do que separado',
        'Всё рождественское в одном наборе — дешевле, чем по отдельности',
        '圣诞限定一次集齐,比单独购买更划算',
        '聖誕限定一次集齊,比單獨購買更划算',
    ],
    'shop.pack.footer': [
        'Nur im Verkaufszeitraum erhältlich. Einmal gekauft, bleibt alles für immer nutzbar.',
        'Only sold during the sale period. Once bought, everything is yours to use forever.',
        'Solo se vende durante el periodo de venta. Una vez comprado, todo es tuyo para siempre.',
        'En vente uniquement pendant la période. Une fois acheté, tout reste utilisable pour toujours.',
        '買えるのは期間中だけです。買ったあとは、期間が終わってもずっと使えます。',
        '기간 중에만 구매할 수 있어요. 구매한 뒤에는 기간이 끝나도 계속 사용할 수 있어요.',
        'Só é vendido durante o período de venda. Depois de comprar, tudo é seu para sempre.',
        'Продаётся только в период продажи. После покупки всё остаётся у вас навсегда.',
        '仅在销售期内可购买。购买后,即使销售期结束也能一直使用。',
        '僅在販售期內可購買。購買後,即使販售期結束也能一直使用。',
    ],
    'publish.mooks.title': [
        'Minion-Look nicht im Besitz', 'Minion look not owned', 'Aspecto de esbirro no adquirido', 'Apparence de sbire non possédée', '持っていない雑魚の見た目です',
        '보유하지 않은 졸개 모습이에요', 'Visual de lacaio não adquirido', 'Облик миньона не куплен', '尚未拥有的小怪造型', '尚未擁有的小怪造型',
    ],
    'publish.mooks.body': [
        'Diese Stage nutzt „%@“. Zum Veröffentlichen brauchst du das Set. (Platzieren und Testen geht auch ohne.)',
        'This stage uses "%@". You need the set to publish. (You can place and test it without owning it.)',
        'Este nivel usa «%@». Necesitas el set para publicar. (Puedes colocarlo y probarlo sin tenerlo.)',
        'Ce niveau utilise « %@ ». Il faut le set pour publier. (Vous pouvez le placer et le tester sans l’avoir.)',
        'このステージは「%@」を使っています。公開するには、このセットが必要です。(置いて試すのは、持っていなくてもできます)',
        '이 스테이지는 "%@"을(를) 사용해요. 공개하려면 이 세트가 필요해요. (배치와 테스트는 없어도 할 수 있어요)',
        'Esta fase usa "%@". Você precisa do conjunto para publicar. (Dá para colocar e testar sem ter.)',
        'В этом уровне используется «%@». Для публикации нужен набор. (Ставить и тестировать можно и без него.)',
        '此关卡使用了“%@”。发布需要拥有此套装。(放置和试玩无需拥有)',
        '此關卡使用了「%@」。發布需要擁有此套裝。(放置和試玩無需擁有)',
    ],
    'publish.mooks.seasonal': [
        'Dieses Set wird nur zeitlich begrenzt verkauft und ist derzeit nicht einzeln erhältlich. Mit dem Lifetime-Paket kannst du es nutzen.',
        'This set is sold for a limited time only and is not sold on its own right now. You can use it with the Lifetime Pack.',
        'Este set solo se vende por tiempo limitado y ahora no se vende por separado. Puedes usarlo con el Pack vitalicio.',
        'Ce set est vendu pour une durée limitée et n’est pas vendu séparément actuellement. Vous pouvez l’utiliser avec le Pack à vie.',
        'このセットは期間限定で、いまは単品では販売していません。永久買い切りパックなら使えます。',
        '이 세트는 기간 한정이라 지금은 단품으로 판매하지 않아요. 영구 구매 팩이 있으면 사용할 수 있어요.',
        'Este conjunto é vendido por tempo limitado e não está à venda separadamente agora. Você pode usá-lo com o Pacote vitalício.',
        'Этот набор продаётся ограниченное время и сейчас отдельно не продаётся. Его можно использовать с пожизненным набором.',
        '此套装为限时销售,目前不单独销售。拥有永久买断包即可使用。',
        '此套裝為限時販售,目前不單獨販售。擁有永久買斷包即可使用。',
    ],
    'editor.mook.trial.note': [
        'Dieser Look ist ein Test: Platzieren und Testspielen geht, zum Veröffentlichen brauchst du das Set.',
        'This look is a trial: you can place and test it, but you need the set to publish.',
        'Este aspecto es de prueba: puedes colocarlo y probarlo, pero necesitas el set para publicar.',
        'Cette apparence est à l’essai : vous pouvez la placer et la tester, mais il faut le set pour publier.',
        'この見た目は「お試し」です。置いてテストプレイまではできます。公開するには、セットが必要です。',
        '이 모습은 "체험"이에요. 배치와 테스트 플레이까지 할 수 있고, 공개하려면 세트가 필요해요.',
        'Este visual é um teste: dá para colocar e testar, mas você precisa do conjunto para publicar.',
        'Этот облик — пробный: ставить и тестировать можно, но для публикации нужен набор.',
        '此造型为“试用”:可以放置并试玩,发布需要拥有套装。',
        '此造型為「試用」:可以放置並試玩,發布需要擁有套裝。',
    ],
    # 設定: 当たり判定の点(どの自機にも、中心の白い点を重ねる。最初はオフ)
    'settings.hitdot': [
        'Trefferpunkt anzeigen', 'Show hit point', 'Mostrar punto de impacto', 'Afficher le point de collision', '当たり判定の点を表示',
        '피격 판정 점 표시', 'Mostrar ponto de colisão', 'Показывать точку попадания', '显示判定点', '顯示判定點',
    ],
    'settings.hitdot.note': [
        'Zeigt bei jedem Schiff einen weißen Punkt in der Mitte – nur dort wirst du getroffen.',
        'Shows a white dot at the center of any ship – that is the only spot bullets can hit.',
        'Muestra un punto blanco en el centro de cualquier nave: solo ahí te alcanzan las balas.',
        'Affiche un point blanc au centre de n’importe quel vaisseau : seul cet endroit peut être touché.',
        'どの自機でも、弾が当たる場所(まん中)に白い点を出します。',
        '어떤 기체든 탄이 맞는 곳(가운데)에 흰 점을 표시합니다.',
        'Mostra um ponto branco no centro de qualquer nave: só ali as balas acertam.',
        'Показывает белую точку в центре любого корабля — пули попадают только в неё.',
        '在任何自机的中心显示白点,只有那里会被子弹击中。',
        '在任何自機的中心顯示白點,只有那裡會被子彈擊中。',
    ],
    # 永久買い切りパックの説明に足す1行(季節に関係なく、年中出す)
    'lifetime.item.5': [
        'Auch zeitlich begrenzte Bosse – jederzeit nutzbar, unabhängig vom Verkaufszeitraum',
        'Limited-time bosses too – usable anytime, in or out of season',
        'También los jefes de tiempo limitado: úsalos cuando quieras, sea o no temporada',
        'Les boss en vente limitée aussi : utilisables à tout moment, hors période comprise',
        '期間限定のボスも、期間に関係なくいつでも使えます',
        '기간 한정 보스도 기간에 상관없이 언제든 사용 가능',
        'Chefes de tempo limitado também: use quando quiser, dentro ou fora da temporada',
        'И боссы с ограниченным сроком продажи — доступны всегда, вне зависимости от периода',
        '限时Boss也包含在内,不受销售期限制,随时可用',
        '限時Boss也包含在內,不受販售期限制,隨時可用',
    ],
    # ショップのボスのカード: 期間限定の目印
    'shop.boss.seasonal': [
        'Zeitlich begrenzter Verkauf', 'Limited-time sale', 'Venta por tiempo limitado', 'Vente limitée', '期間限定販売',
        '기간 한정 판매', 'Venda por tempo limitado', 'Продаётся ограниченное время', '限时销售', '限時販售',
    ],
    'shop.boss.seasonal.note': [
        'Nur im Verkaufszeitraum erhältlich. Einmal gekauft, bleibt der Boss für immer nutzbar. Auch im Lifetime-Paket enthalten.',
        'Only sold during the sale period. Once bought, it is yours to use forever. Also included in the Lifetime Pack.',
        'Solo se vende durante el periodo de venta. Una vez comprado, podrás usarlo para siempre. También incluido en el Pack vitalicio.',
        'En vente uniquement pendant la période. Une fois acheté, il reste utilisable pour toujours. Aussi inclus dans le Pack à vie.',
        '買えるのは期間中だけです。買ったあとは、期間が終わってもずっと使えます。永久買い切りパックにも入っています。',
        '기간 중에만 구매할 수 있어요. 구매한 뒤에는 기간이 끝나도 계속 사용할 수 있어요. 영구 구매 팩에도 포함되어 있어요.',
        'Só é vendido durante o período de venda. Depois de comprar, é seu para usar para sempre. Também incluído no Pacote vitalício.',
        'Продаётся только в период продажи. После покупки остаётся у вас навсегда. Также входит в пожизненный набор.',
        '仅在销售期内可购买。购买后,即使销售期结束也能一直使用。永久买断包也包含此Boss。',
        '僅在販售期內可購買。購買後,即使販售期結束也能一直使用。永久買斷包也包含此Boss。',
    ],
    # エディタ: 持っていない期間限定のボスを、販売していない時期に選んだとき
    'editor.boss.trial.seasonal': [
        'Dieser Boss wird nur zeitlich begrenzt verkauft und ist derzeit nicht erhältlich. Platzieren und Testspielen geht trotzdem. Mit dem Lifetime-Paket ist er jederzeit nutzbar.',
        'This boss is sold for a limited time only and is not on sale right now. You can still place it and test-play. With the Lifetime Pack you can use it anytime.',
        'Este jefe solo se vende por tiempo limitado y ahora no está a la venta. Aun así puedes colocarlo y probarlo. Con el Pack vitalicio puedes usarlo cuando quieras.',
        'Ce boss est vendu pour une durée limitée et n’est pas en vente actuellement. Vous pouvez quand même le placer et le tester. Avec le Pack à vie, il est utilisable à tout moment.',
        '期間限定のボスです。いまは販売していません。置いてテストプレイまではできます。永久買い切りパックなら、いつでも使えます。',
        '기간 한정 보스예요. 지금은 판매하지 않아요. 배치해서 테스트 플레이까지는 할 수 있어요. 영구 구매 팩이 있으면 언제든 사용할 수 있어요.',
        'Este chefe é vendido por tempo limitado e não está à venda agora. Você ainda pode colocá-lo e testar. Com o Pacote vitalício, pode usá-lo quando quiser.',
        'Этот босс продаётся ограниченное время и сейчас недоступен для покупки. Его всё равно можно поставить и опробовать. С пожизненным набором он доступен всегда.',
        '这是限时销售的Boss,目前未在销售。仍可放置并试玩。拥有永久买断包即可随时使用。',
        '這是限時販售的Boss,目前未在販售。仍可放置並試玩。擁有永久買斷包即可隨時使用。',
    ],
    # 公開の画面: 同じ場面
    'publish.boss.seasonal': [
        'Dieser Boss wird nur zeitlich begrenzt verkauft und ist derzeit nicht einzeln erhältlich. Mit dem Lifetime-Paket kannst du ihn nutzen.',
        'This boss is sold for a limited time only and is not sold on its own right now. You can use it with the Lifetime Pack.',
        'Este jefe solo se vende por tiempo limitado y ahora no se vende por separado. Puedes usarlo con el Pack vitalicio.',
        'Ce boss est vendu pour une durée limitée et n’est pas vendu séparément actuellement. Vous pouvez l’utiliser avec le Pack à vie.',
        'このボスは期間限定で、いまは単品では販売していません。永久買い切りパックなら使えます。',
        '이 보스는 기간 한정이라 지금은 단품으로 판매하지 않아요. 영구 구매 팩이 있으면 사용할 수 있어요.',
        'Este chefe é vendido por tempo limitado e não está à venda separadamente agora. Você pode usá-lo com o Pacote vitalício.',
        'Этот босс продаётся ограниченное время и сейчас отдельно не продаётся. Его можно использовать с пожизненным набором.',
        '此Boss为限时销售,目前不单独销售。拥有永久买断包即可使用。',
        '此Boss為限時販售,目前不單獨販售。擁有永久買斷包即可使用。',
    ],
}


def mk(vals):
    assert len(vals) == len(L)
    return {'extractionState': 'manual', 'localizations': {l: {'stringUnit': {'state': 'translated', 'value': v}} for l, v in zip(L, vals)}}


d = json.loads(P.read_text(encoding='utf-8'))
S = d['strings']
for k, v in TEXT.items():
    S[k] = mk(v)
P.write_text(json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ': ')), encoding='utf-8')
print('ok')
