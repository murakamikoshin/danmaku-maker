// App Store Connect に、見た目・撃ち方の買い切り商品(14個)を作る。
// 使い方: Chrome をデバッグ接続(localhost:9222)で起動し、App Store Connect にログインしておく。
//   node tools/asc_create_iaps.mjs <審査用スクリーンショットのPNG | skip> [製品IDの一部で絞り込み]
// 何度流しても、できている部分は飛ばす(途中で止まっても再実行できる)。
import { chromium } from '/Users/murakami/.local/playwright/node_modules/playwright/index.mjs';
import fs from 'fs';

const APP = '6824245206';
const LIST = `https://appstoreconnect.apple.com/apps/${APP}/distribution/iaps`;
const PREFIX = 'com.koshin.danmakumaker.';
const shotPath = process.argv[2];
const only = process.argv[3];

const themes = [
  { id: 'sakura', ja: '桜', en: 'Sakura' },
  { id: 'ocean', ja: '深海', en: 'Deep Sea' },
  { id: 'aurora', ja: 'オーロラ', en: 'Aurora' },
];
const products = [];
for (const t of themes) {
  products.push(
    { id: `${t.id}.bullets`, yen: 100, ref: `${t.en} Bullets`,
      ja: [`${t.ja}の弾`, `弾の色と形が${t.ja}のテーマに変わります。`], en: [`${t.en} Bullets`, 'Changes the color and shape of bullets.'] },
    { id: `${t.id}.background`, yen: 100, ref: `${t.en} Background`,
      ja: [`${t.ja}の背景`, `背景が${t.ja}のテーマに変わります。`], en: [`${t.en} Background`, 'Changes the stage background.'] },
    { id: `${t.id}.ship`, yen: 100, ref: `${t.en} Ship`,
      ja: [`${t.ja}の自機`, `自機の見た目が${t.ja}のテーマに変わります。`], en: [`${t.en} Ship`, 'Changes how your ship looks.'] },
    { id: `${t.id}.set`, yen: 200, ref: `${t.en} Set`,
      ja: [`${t.ja}セット`, `${t.ja}の弾・背景・自機の3点セットです。`], en: [`${t.en} Set`, 'Bullets, background and ship in one set.'] },
  );
}
products.push(
  { id: 'customimages', yen: 500, ref: 'Custom Images', ja: ['じぶんの画像', 'ボス・弾・自機を、自分で選んだ画像に変えます。'], en: ['Your Own Images', 'Use your own pictures for the boss, bullets and ship.'],
    notes: 'This is a one-time (non-consumable) purchase. To test: tap the palette icon at the top left of the home screen to open "Customize & Shop", then buy "Your own images" near the top of the list. After purchase, tap "Choose" next to Boss, Bullets or Your ship and pick any photo. Images are only stored on the device and are never uploaded. Use "Restore Purchases" at the bottom of the same screen to restore it. No account is required.' },
  { id: 'shot.spread', yen: 300, ref: 'Wide Shot', ja: ['ワイドショット', '3方向に少し広がる撃ち方です。'], en: ['Wide Shot', 'A narrow three-way shot style.'] },
  { id: 'shot.heavy', yen: 300, ref: 'Heavy Shot', ja: ['ヘビーショット', '太い1発でダメージ4倍の撃ち方です。'], en: ['Heavy Shot', 'One thick shot with 4x damage.'] },
);

const NOTES = 'This is a one-time (non-consumable) purchase. To test: tap the palette icon at the top left of the home screen to open "Customize & Shop", then buy this item. It becomes available to use right away. Use "Restore Purchases" at the bottom of the same screen to restore it. No account is required.';

const b = await chromium.connectOverCDP('http://localhost:9222');
const ctx = b.contexts()[0];
const p = await ctx.newPage();
const sleep = (ms) => p.waitForTimeout(ms);
const body = async () => (await p.innerText('body')).replace(/\n+/g, ' | ');

// 商品ごとのページ番号。無ければ一覧から集める(tools の使い方は README 相当のコメント参照)
const IDS_FILE = '/private/tmp/claude-501/iap_ids.json';
const ids = fs.existsSync(IDS_FILE) ? JSON.parse(fs.readFileSync(IDS_FILE, 'utf8')) : {};

/** App Store Connect は混むと画面が空のままになるので、文字が出るまで待ち、だめなら読み込み直す */
async function waitFor(text, url) {
  for (let r = 0; r < 4; r++) {
    for (let i = 0; i < 12; i++) {
      if ((await body().catch(() => '')).includes(text)) return;
      await sleep(5000);
    }
    await p.goto(url, { waitUntil: 'domcontentloaded' });
  }
  throw new Error(`page never showed "${text}"`);
}

async function openProduct(prod) {
  const pid = PREFIX + prod.id;
  if (ids[prod.id]) {
    const url = `${LIST}/${ids[prod.id]}`;
    await p.goto(url, { waitUntil: 'domcontentloaded' });
    await waitFor('審査に関する情報', url);
    await sleep(4000);
    return;
  }
  await p.goto(LIST, { waitUntil: 'domcontentloaded' });
  await waitFor('下書き', LIST);
  await p.getByLabel('アプリ内購入の作成').click();
  await sleep(1500);
  await p.selectOption('#inAppPurchaseType', { label: '非消耗型' });
  await p.fill('#name', prod.ref);
  await p.fill('#productId', pid);
  await p.getByRole('button', { name: '作成', exact: true }).click();
  await p.waitForURL(/iaps\/\d+/, { timeout: 30000 });
  ids[prod.id] = p.url().split('/').pop();
  fs.writeFileSync(IDS_FILE, JSON.stringify(ids, null, 1));
  await waitFor('審査に関する情報', p.url());
  await sleep(4000);
}

async function setAvailability() {
  if ((await body()).includes('174個が選択')) return;
  await p.getByRole('button', { name: '配信状況の設定' }).click();
  await sleep(2500);
  await p.getByLabel('中国本土').uncheck();
  await p.getByRole('button', { name: '完了', exact: true }).click();
  await sleep(3000);
}

async function setPrice(yen) {
  if (!(await p.getByRole('button', { name: '価格を追加' }).count())) return;
  await p.getByRole('button', { name: '価格を追加' }).click();
  await sleep(2000);
  await p.getByText('選択する', { exact: true }).click();
  await sleep(800);
  const label = `￥${yen}.00`;
  await p.getByPlaceholder('検索').fill(String(yen));
  await sleep(800);
  await p.getByText(label, { exact: true }).first().click();
  await sleep(800);
  await p.getByRole('button', { name: '次へ' }).click();
  await sleep(3000);
  await p.getByRole('button', { name: '次へ' }).click();
  await sleep(3000);
  await p.getByRole('button', { name: '確認', exact: true }).click();
  await sleep(4000);
}

async function addLocalization(localeLabel, shown, name, desc, first) {
  if ((await body()).includes(`${localeLabel === '日本語' ? '日本語' : '英語（アメリカ）'} | \t | ${name}`)) return;
  if (first) await p.getByRole('button', { name: '追加', exact: true }).first().click();
  else await p.locator('xpath=//*[normalize-space(text())="表示名と説明"]/following::button[1]').first().click();
  await sleep(2000);
  await p.selectOption('select[name=locale]', { label: localeLabel });
  await p.locator('input[name=name]').last().fill(name);
  await p.locator('input[name=description]').fill(desc);
  for (let attempt = 0; attempt < 4; attempt++) {
    await p.getByRole('button', { name: '保存', exact: true }).last().click();
    await sleep(6000);
    if (!(await p.locator('select[name=locale]').count())) return;   // ダイアログが閉じたら保存できた
    await sleep(20000);                                               // 混んでいるときのエラーは、待ってからやり直す
  }
  throw new Error('localization save kept failing');
}

async function setReviewInfo(prod) {
  const input = p.locator('input[id^="iap_review_info"]');
  if (shotPath !== 'skip' && (await input.count())) {
    await input.setInputFiles(shotPath);
    await sleep(5000);
  }
  await p.locator('#iap-or-subscription-review-notes').fill(prod.notes ?? NOTES);
  const save = p.getByRole('button', { name: '保存', exact: true }).first();
  if (await save.isEnabled()) {               // 変更がないときは押せない
    await save.click();
    await sleep(6000);
  }
}

const results = [];
for (const prod of products) {
  if (only && !prod.id.includes(only)) continue;
  try {
    await openProduct(prod);
    await setAvailability();
    await setPrice(prod.yen);
    const t = await body();
    const hasJa = t.includes(`日本語 | \t | ${prod.ja[0]}`);
    const hasEn = t.includes(`英語（アメリカ） | \t | ${prod.en[0]}`);
    const hasAny = t.includes('ローカリゼーション');
    if (!hasJa) await addLocalization('日本語', 'ja', prod.ja[0], prod.ja[1], !hasAny);
    if (!hasEn) await addLocalization('英語（アメリカ）', 'en', prod.en[0], prod.en[1], false);
    await setReviewInfo(prod);
    const final = await body();
    const ok = final.includes('174個が選択') && final.includes(prod.ja[0]) && final.includes(prod.en[0]) && !final.includes('価格を追加');
    results.push(`${ok ? 'OK ' : 'NG '} ${prod.id}`);
  } catch (e) {
    console.log('  ' + String(e).split('\n').slice(0, 6).join(' | '));
    await p.screenshot({ path: `/private/tmp/claude-501/iap_error_${prod.id}.png` }).catch(() => {});
    results.push(`ERR ${prod.id}: ${String(e).split('\n')[0]}`);
  }
  console.log(results[results.length - 1]);
  await sleep(8000);
}
console.log('DONE\n' + results.join('\n'));
process.exit(0);
