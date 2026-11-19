# -*- coding: utf-8 -*-
"""1.4.1: 「いいねしたステージ」の一覧の文言を足す。
使い方: python3 tools/add_liked_strings.py
並びは L と同じ(de, en, es, fr, ja, ko, pt-BR, ru, zh-Hans, zh-Hant)"""
import json, pathlib
P = pathlib.Path(__file__).resolve().parent.parent / 'DanmakuApp/Localizable.xcstrings'
L = ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pt-BR', 'ru', 'zh-Hans', 'zh-Hant']
S = {
    'world.liked.show': ['Gelikte Level', 'Stages you liked', 'Niveles que te gustan', 'Niveaux que vous aimez', 'いいねしたステージ',
                         '좋아요한 스테이지', 'Fases que você curtiu', 'Понравившиеся уровни', '我点赞的关卡', '我按讚的關卡'],
    'world.liked.empty': ['Noch keine gelikten Level. Tippe bei einem Level auf das Herz, dann erscheint es hier.',
                          'No liked stages yet. Tap the heart on a stage and it will show up here.',
                          'Aún no te ha gustado ningún nivel. Toca el corazón de un nivel y aparecerá aquí.',
                          "Aucun niveau aimé pour l'instant. Touchez le cœur d'un niveau pour le retrouver ici.",
                          'まだいいねしたステージはありません。ステージの画面でハートを押すと、ここに出ます。',
                          '아직 좋아요한 스테이지가 없어요. 스테이지 화면에서 하트를 누르면 여기에 나와요.',
                          'Você ainda não curtiu nenhuma fase. Toque no coração de uma fase para vê-la aqui.',
                          'Понравившихся уровней пока нет. Нажмите на сердечко на странице уровня, и он появится здесь.',
                          '还没有点赞的关卡。在关卡页面点爱心后，会显示在这里。',
                          '還沒有按讚的關卡。在關卡頁面點愛心後，會顯示在這裡。'],
}
d = json.loads(P.read_text(encoding='utf-8'))
for k, vals in S.items():
    d['strings'][k] = {'extractionState': 'manual', 'localizations': {l: {'stringUnit': {'state': 'translated', 'value': v}} for l, v in zip(L, vals)}}

P.write_text(json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ': ')), encoding='utf-8')
print('ok')
