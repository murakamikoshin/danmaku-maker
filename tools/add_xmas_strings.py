# -*- coding: utf-8 -*-
"""期間限定のボス(1.5.0)の売り場まわりの文言を、Localizable.xcstrings の10言語に書き込む。何度流しても同じ結果。
使い方: python3 tools/add_xmas_strings.py
並びは L と同じ(de, en, es, fr, ja, ko, pt-BR, ru, zh-Hans, zh-Hant)
ボスの名前・技の名前(enemy.boss.14 など)は、絵と技が決まってから足す"""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent.parent / 'DanmakuApp/Localizable.xcstrings'
L = ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant']

TEXT = {
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
