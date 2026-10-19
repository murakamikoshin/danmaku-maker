// RevenueCat の商品カタログに、買い切り商品(広告削除 + 14商品)を登録する(識別子と名前だけで、秘密情報は使わない)。
// 使い方: Chrome をデバッグ接続(localhost:9222)で起動し、RevenueCat にログインしておく。 node tools/rc_create_products.mjs
import { chromium } from '/Users/murakami/.local/playwright/node_modules/playwright/index.mjs';

const PREFIX = 'com.koshin.danmakumaker.';
const APP = 'https://app.revenuecat.com/projects/c60cfbbd/apps/app568ad57b69/products/new';
const themes = [['sakura', 'Sakura'], ['ocean', 'Deep Sea'], ['aurora', 'Aurora']];
const items = [['removeads', 'Remove Ads']];
for (const [id, en] of themes) {
  items.push([`${id}.bullets`, `${en} Bullets`], [`${id}.background`, `${en} Background`], [`${id}.ship`, `${en} Ship`], [`${id}.set`, `${en} Set`]);
}
items.push(['shot.spread', 'Wide Shot'], ['shot.heavy', 'Heavy Shot'], ['customimages', 'Custom Images']);
const only = process.argv[2];

const b = await chromium.connectOverCDP('http://localhost:9222');
const p = await b.contexts()[0].newPage();
const results = [];
for (const [id, name] of items) {
  if (only && !id.includes(only)) continue;
  try {
    await p.goto(APP, { waitUntil: 'domcontentloaded' });
    const ident = p.locator('#app_store-product-identifier');
    await ident.waitFor({ timeout: 60000 });
    await ident.click();
    await p.keyboard.type(PREFIX + id, { delay: 5 });
    await p.locator('#display_name').click();
    await p.keyboard.type(name, { delay: 5 });
    await p.getByText('Non-consumable', { exact: true }).click();
    await p.getByRole('button', { name: 'Create Product' }).click();
    await p.waitForTimeout(5000);
    const url = p.url();
    results.push(`${url.includes('/products/new') ? 'NG ' : 'OK '} ${id}  ${url.split('/').slice(-2).join('/')}`);
  } catch (e) {
    results.push(`ERR ${id}: ${String(e).split('\n')[0]}`);
  }
  console.log(results[results.length - 1]);
}
console.log('DONE');
process.exit(0);
