// 各アプリ内購入のページで「審査用に追加」を押して、提出物の下書きに入れる(提出そのものはしない。最後の「審査へ提出」は人が押す)。
import { chromium } from '/Users/murakami/.local/playwright/node_modules/playwright/index.mjs';
import fs from 'fs';
const ids = JSON.parse(fs.readFileSync('/private/tmp/claude-501/iap_ids.json', 'utf8'));
const b = await chromium.connectOverCDP('http://localhost:9222');
const p = b.contexts()[0].pages().find((x) => x.url().includes('appstoreconnect')) ?? await b.contexts()[0].newPage();
const results = [];
for (const [key, id] of Object.entries(ids)) {
  try {
    const url = `https://appstoreconnect.apple.com/apps/6824245206/distribution/iaps/${id}`;
    let ok = false;
    for (let i = 0; i < 4 && !ok; i++) {
      await p.goto(url, { waitUntil: 'domcontentloaded' });
      for (let j = 0; j < 10 && !ok; j++) { await p.waitForTimeout(4000); ok = (await p.innerText('body')).includes('審査に関する情報'); }
    }
    await p.waitForTimeout(3000);
    const body = await p.innerText('body');
    if (body.includes('この項目は審査用に追加されています')) { results.push(`ALREADY ${key}`); console.log(results.at(-1)); continue; }
    const btn = p.getByRole('button', { name: '審査用に追加', exact: true }).first();
    if (!(await btn.isEnabled())) { results.push(`DISABLED ${key}`); console.log(results.at(-1)); continue; }
    await btn.click();
    await p.waitForTimeout(2500);
    // 下書きがすでにあると、メニューが出る。既存の下書き(作成者の行)を選ぶ
    const entry = p.getByText('作成者：', { exact: false }).first();
    if (await entry.count()) { await entry.click(); await p.waitForTimeout(6000); }
    const after = await p.innerText('body');
    results.push(`${after.includes('審査用に追加されています') ? 'ADDED  ' : 'CHECK  '} ${key}`);
  } catch (e) {
    results.push(`ERR ${key}: ${String(e).split('\n')[0]}`);
  }
  console.log(results.at(-1));
}
console.log('DONE');
process.exit(0);
