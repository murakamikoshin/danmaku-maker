雪の女王(ice) のドット絵

- 1コマの大きさ: 全コマ 112×112 ピクセル、背景は透明(PNG・RGBA、透明度は0か255だけ)
- 向き: 正面(下向き)。体の中心は全コマ同じ位置。拡大は必ず最近傍補間(.nearest)
- ファイル名: ice_<状態>_<コマ番号>.png

状態ごとのコマ数とループの順番:
- idle: 8コマ。0→1→…→7 でループ
- windup: 4コマ。0→3 の順に1回
- attack: 4コマ。0→3 でループ
- recover: 2コマ。0→1 の順に1回(そのあと待機へ)
- idle_awakened: 8コマ。0→1→…→7 でループ

- 待機(idle)は元の絵(handoff/sheets)をそのまま1コマずつに分けたもの
- 核は背後の結晶の中心。覚醒後は紅の氷に染まり、うしろに放射する光と、体のふちの点滅する光がつく
- 構え・技中・硬直では、体を少し傾けて真正面一辺倒にならないようにしている(行ごとの整数ずらしなので、ぼけない)
- 再生の目安: 1コマ 0.12 秒(状態ごとのGIFと同じ)

使った色(82色):
  #0B0612 #0C0715 #0C0815 #0E0306 #163C6D #174278 #1A5AA0 #3D5B86
  #436594 #4A74A8 #4A85A8 #4E6F8D #516586 #5281BA #5295BA #54769A
  #5A7094 #5A8CC8 #5B6C8B #5D84AA #5E99A8 #655072 #65799A #68ABBA
  #6E88A2 #6FB4FF #6FD0FF #70597E #76889F #781E3C #7A98B3 #7A9CC8
  #7C94A8 #7F8CA1 #7FB8E8 #800429 #82707B #8498B0 #8AA6BA #8AA8D0
  #8CD2FF #8E96A8 #8E9DB3 #8FF0FF #90698F #909DA8 #917D87 #9A7AA8
  #9A8F93 #9DA0A8 #9EA8BA #A03A59 #A0586D #A1AFBA #A4A2A8 #A66579
  #A8D4F5 #ACA0A2 #AFB3BA #B6D4F0 #B7B6BA #B95975 #BFE8FF #C1C1DF
  #C47D92 #C4DCF4 #C9AEB6 #CBD3ED #CC476F #CC6483 #CDC8E2 #DCECFF
  #E0F6FF #E3D6ED #E6DEED #EFE0DC #F4FBFF #F6E2ED #FF78A0 #FFAAC8
  #FFE5ED #FFFFFF

描き直すとき: python3 make_ice.py(共通処理は ../tools/bosskit.py)
