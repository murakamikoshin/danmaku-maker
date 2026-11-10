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
for (const [id, name] of [['homing', 'Homing Pattern'], ['pattern.flower', 'Flower Pattern'], ['pattern.star', 'Star Pattern'], ['pattern.heart', 'Heart Pattern'], ['pattern.beam', 'Beam Pattern'], ['pattern.cross', 'Cross Pattern'], ['pattern.accel', 'Accelerate Pattern'], ['pattern.bounce', 'Bounce Pattern'], ['pattern.stopgo', 'Stop and Go Pattern'], ['pattern.split', 'Split Pattern'], ['pattern.timed', 'Delayed Pattern'], ['patternpack', 'Pattern Pack'], ['patternmaker', 'Pattern Maker'], ['boss.fallen_angel', 'Fallen Angel Boss'], ['boss.kitsune', 'Nine-Tailed Shrine Maiden Boss'], ['boss.ice_queen', 'Snow Queen Boss'], ['boss.reaper', 'Reaper Boss'], ['boss.witch', 'Deep-Sea Witch Boss'], ['boss.mech', 'Mech Deity Boss'], ['boss.hire', 'Goldfish Princess Boss'], ['lifetime', 'Lifetime Pack']]) items.push([id, name]);
// 弾幕パック2(2026-10-31 追加)
for (const [id, name] of [['pattern.mine', 'Mine Pattern'], ['pattern.meteor', 'Meteor Pattern'], ['pattern.gridLaser', 'Grid Laser Pattern'], ['pattern.sweepLaser', 'Sweeping Laser Pattern'], ['pattern.giantOrb', 'Giant Orb Pattern'], ['pattern.bubble', 'Swelling Bubble Pattern'], ['pattern.gravity', 'Gravity Shot Pattern'], ['pattern.orbit', 'Satellites Pattern'], ['pattern.snake', 'Snake Pattern'], ['pattern.shatterRing', 'Shatter Ring Pattern'], ['pattern.homingRing', 'Homing Ring Pattern'], ['patternpack2', 'Pattern Pack 2']]) items.push([id, name]);
const only = process.argv[2];

const b = await chromium.connectOverCDP('http://127.0.0.1:9222');
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
