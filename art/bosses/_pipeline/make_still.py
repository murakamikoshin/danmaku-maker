"""元のイラスト → ボスのドット絵(1枚)。決まった作り方(2026-11-10 に決定、「D3」の設定):
1. pixel4.py   ドット化(高さ66)。黒い線は色つきの輪郭に置き換え、黒い物の面だけ残す
2. material.py 素材ごとに色をそろえる(色は3段、肌と白は2段、散った点の多数決1回)
3. degrey.py   灰色を消す
4. face5.py    目(赤の縦長 2×3、上にまぶたの影)と口を置き直す。目のまわりのノイズも消す
5. polish_<ID>.py があれば、キャラごとの手直し(持ち物の形など)
6. degrey.py   もう一度灰色を消す
使い方: python3 make_still.py <ボスのフォルダ>   (フォルダの source/ に <ID>_source.png と <ID>_face.json を置く)
顔の座標(<ID>_face.json)は、高さ88で作ったときのマスで書く(高さ66に合わせて自動で 0.75 倍する)"""
import os, sys, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
HEIGHT, COLORS, LEVELS, PASSES, LEVELS_LIGHT = 66, 24, 3, 1, 2
def run(*a, env=None): subprocess.run([sys.executable, *a], check=True, env=env, stdout=subprocess.DEVNULL)
def make(folder):
    bid = os.path.basename(os.path.abspath(folder)); S = os.path.join(folder, 'source')
    src, face, still = (os.path.join(S, f'{bid}_{k}') for k in ('source.png', 'face.json', 'still.png'))
    env = dict(os.environ, K=str(HEIGHT / 88))
    run(f'{HERE}/pixel4.py', src, still, str(HEIGHT), str(COLORS))
    run(f'{HERE}/material.py', still, still, str(LEVELS), str(PASSES), str(LEVELS_LIGHT))
    run(f'{HERE}/degrey.py', still, still)
    run(f'{HERE}/face5.py', still, face, env=env)
    pol = os.path.join(S, f'polish_{bid}.py')
    if os.path.exists(pol): run(pol, still, still, env=env)
    run(f'{HERE}/degrey.py', still, still)
    return still
if __name__ == '__main__': print(make(sys.argv[1]))
