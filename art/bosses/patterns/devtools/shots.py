"""試射場のページを開いて、ドラゴンの技の画面を撮る(見た目の確認用)。Playwright が要る。
使い方:
  python3 art/bosses/patterns/build.py /tmp/out/boss_patterns.html      # 先にページを作る
  python3 shots.py /tmp/out/boss_patterns.html sheet <姿0-3> <出力.png> [ms,ms,...] [技ID,技ID,...]
      全部の技(または指定した技)を、指定した時刻(ミリ秒。初期値 1500,2600,3700,5000)に1枚ずつ撮って並べる
  python3 shots.py /tmp/out/boss_patterns.html burst <姿0-3> <技ID|form> <開始ms> <間隔ms> <枚数> <出力.png>
      1つの技を連続で撮る。技ID の代わりに form と書くと、姿を切り替えた瞬間を撮る
注意: 1枚撮るのに 0.1 秒くらいかかるので、時刻は目安。速い動き(尻尾の薙ぎ払いなど)は何度か撮り直す
Chrome の場所は環境変数 CHROME で指定できる(なければ Playwright の Chromium)"""
import asyncio, os, sys, tempfile
from playwright.async_api import async_playwright
from PIL import Image
page, mode, lv = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
async def main():
    async with async_playwright() as p:
        kw = dict(args=['--no-sandbox']); exe = os.environ.get('CHROME')
        if exe: kw['executable_path'] = exe
        b = await p.chromium.launch(**kw); pg = await b.new_page(viewport={'width': 1100, 'height': 1300}); errs = []
        pg.on('pageerror', lambda e: errs.append(str(e)))
        await pg.goto('file://' + page); await pg.wait_for_timeout(1000)
        await pg.click('#bosses button[data-v="dragon"]'); await pg.wait_for_timeout(1200)
        tmp = os.path.join(tempfile.gettempdir(), 'danmaku_shot.png')
        async def snap():
            await pg.locator('#field').screenshot(path=tmp); return Image.open(tmp).convert('RGB').copy()
        if mode == 'sheet':
            out = sys.argv[4]; times = [int(x) for x in (sys.argv[5] if len(sys.argv) > 5 else '1500,2600,3700,5000').split(',')]
            await pg.click(f'#form button[data-lv="{lv}"]'); await pg.wait_for_timeout(1500)
            ids = await pg.evaluate("[...document.querySelectorAll('#pats button')].map(b=>b.dataset.v)")
            if len(sys.argv) > 6: ids = [i for i in ids if i in sys.argv[6].split(',')]
            rows = []
            for pid in ids:
                await pg.click(f'#pats button[data-v="{pid}"]'); ims = []; last = 0
                for t in times: await pg.wait_for_timeout(t - last); last = t; ims.append(await snap())
                rows.append(ims)
        else:
            pid, t0, dt, n, out = sys.argv[4], int(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7]), sys.argv[8]
            await pg.click(f'#form button[data-lv="{lv}"]')
            if pid != 'form': await pg.wait_for_timeout(300); await pg.click(f'#pats button[data-v="{pid}"]')
            await pg.wait_for_timeout(t0); ims = []
            for k in range(n): ims.append(await snap()); await pg.wait_for_timeout(dt)
            rows = [ims]
        w, h = rows[0][0].size; sheet = Image.new('RGB', (w * len(rows[0]), h * len(rows)))
        for r, ims in enumerate(rows):
            for c, im in enumerate(ims): sheet.paste(im, (c * w, r * h))
        sheet.save(out); print(out, sheet.size, 'ページのエラー:', errs[:5])
        await b.close()
asyncio.run(main())
