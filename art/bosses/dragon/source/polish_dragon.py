"""ドラゴンの顔を描き直す(元絵の頭は小さく、ドットにすると目と口がつぶれるため)。座標はドット絵のマス(高さ112)。
顔の左半分(x=66〜76)を文字の絵で書いて、左右対称に置く。使い方: python3 polish_dragon.py 入力.png 出力.png"""
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGBA'); P = im.load()
COL = {'G': (232, 172, 56), 'g': (172, 112, 32), 'Y': (255, 224, 124),      # 金: ふつう・暗い・明るい
       'R': (190, 34, 32), 'r': (128, 16, 28), 'L': (236, 84, 52),          # 赤: ふつう・暗い・明るい
       'S': (70, 6, 22), 'E': (255, 255, 236), 'T': (255, 244, 224)}        # 影・目(光る)・牙
X0, Y0, CX = 66, 19, 153        # 絵の左上、左右対称の軸(x と CX - x)
FACE = [
 "......rRRRL",
 ".....rRRRRL",
 ".ggrrRRRRRL",   # まゆの骨(金)が外の上から内の下へ: にらむ形
 "..SggrRRRRL",
 "..EESggrRRL",   # 目はまゆの下で、外が上がる細いつり目(光る1色)
 "..SEEESggRL",
 "..rSSEESggL",
 ".rrrrSSSSRL",
 ".rrrRRRRRRL",   # 口先は下へ行くほど細い
 ".rrrrRRRRRL",
 "..rrrRRRRRL",
 "..rrrrRRRRL",
 "..SrrrRRSRL",   # 鼻の穴、口の端(上がる)
 "...SrrRRRRR",
 "...rSSSSSSS",   # 閉じた口
 "...rrTSTSTS",   # 牙
 "...rrTgggGG",
 "....rrgGGGY",   # 下あご(金)
 "....rrrgGGG",
 ".....rrrgGG",
 "......rrrgg",
]
for j, row in enumerate(FACE):
    for i, ch in enumerate(row):
        if ch == '.': continue
        for x in (X0 + i, CX - (X0 + i)):
            if P[x, Y0 + j][3]: P[x, Y0 + j] = COL[ch] + (255,)
im.save(sys.argv[2])
