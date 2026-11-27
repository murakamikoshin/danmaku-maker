// App Store Connect に、見た目・撃ち方・弾幕などの買い切り商品を作る(弾幕パック2の12個も、2026-10-31 に追加)。
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
const patterns = [
  ['homing', 'Homing', '追尾', '自機を追いかけて曲がる弾幕です。', 'Bullets that curve toward your ship.', 300],
  ['pattern.flower', 'Flower', '花', '花の形に広がる弾幕です。', 'A flower-shaped bullet pattern.', 100],
  ['pattern.star', 'Star', '星', '星の形に広がる弾幕です。', 'A star-shaped bullet pattern.', 100],
  ['pattern.heart', 'Heart', 'ハート', 'ハートの形に広がる弾幕です。', 'A heart-shaped bullet pattern.', 100],
  ['pattern.beam', 'Bullet Line', '一列弾', '一直線に伸びる光線の弾幕です。', 'A straight beam of bullets.', 100],
  ['pattern.cross', 'Cross', '十字', '上下左右に伸びる弾幕です。', 'Bullets stretching in four directions.', 100],
  ['pattern.accel', 'Accelerate', '加速', 'どんどん速くなる弾幕です。', 'Bullets that keep speeding up.', 100],
  ['pattern.bounce', 'Bounce', '反射', '壁ではね返る弾幕です。', 'Bullets that bounce off the walls.', 100],
  ['pattern.stopgo', 'Stop & Go', 'ストップ&ゴー', 'ぴたっと止まって、飛び出す弾幕です。', 'Bullets that stop, then dash at you.', 100],
  ['pattern.split', 'Split', '分裂', '途中で小さな弾にはじける弾幕です。', 'Bullets that burst into smaller ones.', 100],
  ['pattern.timed', 'Delayed', '時差', '止まってから、いっせいに動く弾幕です。', 'A frozen ring that moves all at once.', 100],
];
const patternNotes = 'This is a one-time (non-consumable) purchase. To test: open the Shop tab (bottom of the screen), scroll to "Bullet patterns" and buy this item. It then becomes available in the stage editor (the lock on the pattern tile disappears). Anyone can play stages that use it. Use "Restore Purchases" at the bottom of the Shop screen to restore it. No account is required.';
for (const [id, en, ja, jaDesc, enDesc, yen] of patterns) {
  products.push({ id, yen, ref: `${en} Pattern`, ja: [`${ja}の弾幕`, jaDesc], en: [`${en} Pattern`, enDesc], notes: patternNotes });
}
products.push({ id: 'patternpack', yen: 600, ref: 'Pattern Pack', ja: ['弾幕パック(全部入り)', '買える弾幕11種類が、すべて使えるようになります。'], en: ['All Patterns Pack', 'Unlocks all 11 paid bullet patterns.'], notes: patternNotes });
// 弾幕パック2(2026-10-31 追加): バラ11個と全部入り。ショップの「弾幕パック2」のカードで買える
const pattern2Notes = patternNotes.replace('scroll to "Bullet patterns"', 'scroll to "Bullet patterns 2"');
for (const [id, en, ja, jaDesc, enDesc, yen] of [
  ['pattern.mine', 'Mine', '地雷', '止まって点滅し、爆発する弾幕です。', 'Mines that stop, blink and explode.', 300],
  ['pattern.meteor', 'Meteor', '隕石', '予告の円に、大きな衝撃が落ちる弾幕です。', 'A big impact lands on a warning circle.', 300],
  ['pattern.gridLaser', 'Grid Laser', '格子レーザー', '縦と横の光線を格子に撃つ弾幕です。', 'Lasers that form a grid.', 300],
  ['pattern.sweepLaser', 'Sweeping Laser', 'なぎ払いレーザー', '光線が画面をなぎ払う弾幕です。', 'A laser that sweeps the screen.', 100],
  ['pattern.giantOrb', 'Giant Orb', '巨大弾', '大きな弾を1発ずつ撃つ弾幕です。', 'One huge orb at a time.', 100],
  ['pattern.bubble', 'Swelling Bubble', '膨らむ泡', 'だんだん大きくなる泡の弾幕です。', 'Bubbles that keep getting bigger.', 100],
  ['pattern.gravity', 'Gravity Shot', '重力弾', '投げ上げて落ちてくる弾幕です。', 'Bullets that arc up and fall.', 100],
  ['pattern.orbit', 'Satellites', '衛星', '回ってから飛び出す弾幕です。', 'Bullets that orbit, then fly out.', 100],
  ['pattern.snake', 'Snake', 'スネーク', '列になって追いかける弾幕です。', 'A line of bullets that chases you.', 100],
  ['pattern.shatterRing', 'Shatter Ring', '破裂の輪', '輪がはじけて散る弾幕です。', 'A ring that bursts into pieces.', 100],
  ['pattern.homingRing', 'Homing Ring', '追尾の輪', '輪が広がってから追いかける弾幕です。', 'A ring that curves toward you.', 100],
]) {
  products.push({ id, yen, ref: `${en} Pattern`, ja: [`${ja}の弾幕`, jaDesc], en: [`${en} Pattern`, enDesc], notes: pattern2Notes });
}
products.push({ id: 'patternpack2', yen: 600, ref: 'Pattern Pack 2', ja: ['弾幕パック2(全部入り)', '弾幕パック2の11種類が、すべて使えるようになります。'], en: ['Patterns Pack 2', 'Unlocks all 11 patterns in Pack 2.'], notes: pattern2Notes });
// 弾幕パック3(2026-11-23 追加。1.4.2): バラ11個と全部入り。ショップの「弾幕パック3」のカードで買える
const pattern3Notes = patternNotes.replace('scroll to "Bullet patterns"', 'scroll to "Bullet patterns 3"');
for (const [id, en, ja, jaDesc, enDesc, yen] of [
  ['pattern.radialLaser', 'Omni Laser', '全方位レーザー', '全方向に光線を撃ち、ゆっくり回る弾幕です。', 'Beams in every direction that slowly turn.', 300],
  ['pattern.lightning', 'Lightning Strike', '落雷', '画面の上から雷が落ちる弾幕です。', 'Bolts strike down from the top.', 300],
  ['pattern.carpetBomb', 'Carpet Bomb', '爆撃ライン', '爆発が自機へ向かって連なる弾幕です。', 'A chain of explosions rolls toward you.', 300],
  ['pattern.dashShot', 'Dash Shot', '急加速弾', 'ゆっくり出て急に加速する弾幕です。', 'Slow bullets that suddenly dash.', 100],
  ['pattern.implode', 'Implosion', '吸い込み弾', '大きな輪から中心へ集まる弾幕です。', 'Bullets rush in from a wide ring.', 100],
  ['pattern.pincer', 'Pincer Attack', '挟み撃ち', '画面の左右から同時に飛んでくる弾幕です。', 'Shots from both sides at once.', 100],
  ['pattern.whirlwind', 'Whirlwind', 'つむじ風', '回る弾のかたまりが流れてくる弾幕です。', 'A spinning cluster drifts toward you.', 100],
  ['pattern.bounceBall', 'Bouncing Ball', 'バウンドボール', '放物線で落ちて床ではねる弾幕です。', 'Balls that arc down and bounce.', 100],
  ['pattern.needle', 'Needles', 'ニードル', '細長い針を扇状に撃つ弾幕です。', 'A fan of long, thin needles.', 100],
  ['pattern.trackLaser', 'Tracking Laser', '追跡レーザー', '自機を追ってから撃つ光線の弾幕です。', 'A laser that tracks you, then fires.', 100],
  ['pattern.blinkShot', 'Blink Shot', '瞬間移動弾', '消えては先に現れる弾幕です。', 'Bullets that vanish and reappear ahead.', 100],
]) {
  products.push({ id, yen, ref: `${en} Pattern`, ja: [`${ja}の弾幕`, jaDesc], en: [`${en} Pattern`, enDesc], notes: pattern3Notes });
}
products.push({ id: 'patternpack3', yen: 600, ref: 'Pattern Pack 3', ja: ['弾幕パック3(全部入り)', '弾幕パック3の11種類が、すべて使えるようになります。'], en: ['Patterns Pack 3', 'Unlocks all 11 patterns in Pack 3.'], notes: pattern3Notes });
products.push(
  { id: 'customimages', yen: 500, ref: 'Custom Images', ja: ['じぶんの画像', 'ボス・弾・自機を、自分で選んだ画像に変えます。'], en: ['Your Own Images', 'Use your own pictures for the boss, bullets and ship.'],
    notes: 'This is a one-time (non-consumable) purchase. To test: tap the palette icon at the top left of the home screen to open "Customize & Shop", then buy "Your own images" near the top of the list. After purchase, tap "Choose" next to Boss, Bullets or Your ship and pick any photo. Images are only stored on the device and are never uploaded. Use "Restore Purchases" at the bottom of the same screen to restore it. No account is required.' },
  { id: 'shot.spread', yen: 300, ref: 'Wide Shot', ja: ['ワイドショット', '3方向に少し広がる撃ち方です。'], en: ['Wide Shot', 'A narrow three-way shot style.'] },
  { id: 'shot.heavy', yen: 300, ref: 'Heavy Shot', ja: ['ヘビーショット', '太い1発でダメージ4倍の撃ち方です。'], en: ['Heavy Shot', 'One thick shot with 4x damage.'] },
);

const makerNotes = 'This is a one-time (non-consumable) purchase. To test: open the Shop tab (bottom of the screen), scroll to "Pattern Maker" and buy it. A "Create" button then appears: tap it, draw a line with your finger in the box (bullets follow the line at the speed you draw), tap Save, and the pattern becomes selectable in the stage editor. Anyone can play stages that use the patterns without buying. Use "Restore Purchases" at the bottom of the Shop screen to restore it. No account is required.';
const lifetimeNotes = 'This is a one-time (non-consumable) purchase. To test: open the Shop tab (bottom of the screen); the "Lifetime Pack" card is at the top. After purchase, every paid item (looks, shots, patterns, custom images, Pattern Maker) is unlocked, ads are removed (no banner ads, free revives), and the daily limit on publishing stages no longer applies. Items added in the future are included. Use "Restore Purchases" at the bottom of the Shop screen to restore it. No account is required.';
const bossNotes = 'This is a one-time (non-consumable) purchase. To test: open the Shop tab (bottom of the screen) and open the "Bosses" tab at the top. Buy "Fallen Angel". It can then be placed as the boss of a stage you publish (Create tab > Boss mode > Advanced > Boss look). Anyone can play stages that use the boss without buying; it can also be tried in the editor before buying, and is only needed to publish. Use "Restore Purchases" at the top of the Shop screen to restore it. No account is required.';
products.push(
  { id: 'boss.fallen_angel', yen: 400, ref: 'Boss Fallen Angel', ja: ['堕天使', 'ステージに置けるボス「堕天使」。5つの技と覚醒つき。'], en: ['Fallen Angel', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.kitsune', yen: 400, ref: 'Boss Nine-Tailed Shrine Maiden', ja: ['九尾の巫女', 'ステージに置けるボス「九尾の巫女」。5つの技と覚醒つき。'], en: ['Nine-Tailed Shrine Maiden', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.ice_queen', yen: 400, ref: 'Boss Snow Queen', ja: ['雪の女王', 'ステージに置けるボス「雪の女王」。5つの技と覚醒つき。'], en: ['Snow Queen', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.reaper', yen: 400, ref: 'Boss Reaper', ja: ['死神', 'ステージに置けるボス「死神」。5つの技と覚醒つき。'], en: ['Reaper', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.witch', yen: 400, ref: 'Boss Deep-Sea Witch', ja: ['深海の魔女', 'ステージに置けるボス「深海の魔女」。5つの技と覚醒つき。'], en: ['Deep-Sea Witch', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.hire', yen: 400, ref: 'Boss Goldfish Princess', ja: ['金魚姫', 'ステージに置けるボス「金魚姫」。5つの技と覚醒つき。'], en: ['Goldfish Princess', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.mech', yen: 400, ref: 'Boss Mech Deity', ja: ['機神', 'ステージに置けるボス「機神」。5つの技と覚醒つき。'], en: ['Mech Deity', 'A boss for your stages, with 5 moves and awakening.'], notes: bossNotes },
  { id: 'boss.dragon', yen: 1200, ref: 'Boss Dragon King', ja: ['竜王', 'ステージに置ける大型ボス「竜王」。15の技と4つの姿つき。'], en: ['Dragon King', 'A huge boss for your stages, with 15 moves and 4 forms.'],
    notes: bossNotes.replace('Buy "Fallen Angel"', 'Buy "Dragon King"') },
  { id: 'patternmaker', yen: 1000, ref: 'Pattern Maker', ja: ['弾幕作成モード', '指で線を描いて、自分だけの弾幕を作れます。'], en: ['Pattern Maker', 'Draw a line to make your own bullet pattern.'], notes: makerNotes },
  { id: 'lifetime', yen: 3000, ref: 'Lifetime Pack', ja: ['永久買い切りパック', '全部の課金コンテンツと広告削除を、今後の追加分もずっと。'], en: ['Lifetime Pack', 'All paid items and Remove Ads, forever.'], notes: lifetimeNotes },
);

// クリスマス(2026-11-27 追加。1.5.0): 期間限定の10個。期間外はアプリの売り場に出ない(サンドボックス・審査では、いつでも出る)
const xmasNote = (where) => `This is a one-time (non-consumable) purchase, sold for a limited time (Christmas, Dec 1 - Dec 26). In the sandbox (TestFlight / App Review) it is always on sale. To test: open the Shop tab (bottom of the screen), ${where}. Anyone can play stages that use these items without buying; they are only needed to publish a stage that uses them. Use "Restore Purchases" in the Shop to restore it. No account is required.`;
products.push(
  { id: 'boss.santa', yen: 400, ref: 'Boss Santa Girl Noel', ja: ['サンタ娘 ノエル', 'ステージに置ける期間限定のボス。5つの技と覚醒つき。'], en: ['Santa Girl Noel', 'A limited-time boss with 5 moves and awakening.'],
    notes: xmasNote('open the "Bosses" tab at the top and buy "Noel". It can then be used as the boss of a stage you publish (Create tab > Boss mode > Advanced > Boss look); it also unlocks the "Christmas" BGM') },
  { id: 'mooks.xmas', yen: 200, ref: 'Christmas Minions', ja: ['クリスマスの雑魚セット', 'ステージの雑魚を、クリスマスの見た目4種に。'], en: ['Christmas Minions', '4 Christmas looks for the minions in your stages.'],
    notes: xmasNote('open the "Bosses" tab at the top and buy "Christmas Minions". The 4 minion looks can then be used in stages you publish (Create tab > Advanced > Minion look)') },
  { id: 'ship.sleigh_xmas', yen: 100, ref: 'Ship Sleigh', ja: ['自機「そり」', 'クリスマスのドット絵の自機です。'], en: ['Sleigh Ship', 'A Christmas pixel-art ship.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Sleigh" in the ships section, then tap "Use"') },
  { id: 'ship.reindeer_xmas', yen: 100, ref: 'Ship Reindeer', ja: ['自機「トナカイ」', 'クリスマスのドット絵の自機です。'], en: ['Reindeer Ship', 'A Christmas pixel-art ship.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Reindeer" in the ships section, then tap "Use"') },
  { id: 'ship.snowflake_xmas', yen: 100, ref: 'Ship Snowflake', ja: ['自機「雪の結晶」', 'クリスマスのドット絵の自機です。'], en: ['Snowflake Ship', 'A Christmas pixel-art ship.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Snowflake" in the ships section, then tap "Use"') },
  { id: 'xmas.bullets', yen: 100, ref: 'Christmas Bullets', ja: ['クリスマスの弾', '弾の色と形がクリスマスのテーマに変わります。'], en: ['Christmas Bullets', 'Changes the color and shape of bullets.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Bullets" on the "Christmas" theme card') },
  { id: 'xmas.background', yen: 100, ref: 'Christmas Background', ja: ['クリスマスの背景', '背景がクリスマスのテーマに変わります。'], en: ['Christmas Background', 'Changes the stage background.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Background" on the "Christmas" theme card') },
  { id: 'xmas.ship', yen: 100, ref: 'Christmas Ship', ja: ['クリスマスの自機', '自機の見た目がクリスマスのテーマに変わります。'], en: ['Christmas Ship', 'Changes how your ship looks.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Ship" on the "Christmas" theme card') },
  { id: 'xmas.set', yen: 200, ref: 'Christmas Set', ja: ['クリスマスセット', 'クリスマスの弾・背景・自機の3点セットです。'], en: ['Christmas Set', 'Bullets, background and ship in one set.'],
    notes: xmasNote('open the "Looks" tab at the top and buy "Set" on the "Christmas" theme card') },
  { id: 'pack.xmas', yen: 600, ref: 'Christmas Pack', ja: ['クリスマスパック', 'ノエル・雑魚セット・自機3種・テーマをまとめてお得に。'], en: ['Christmas Pack', 'Noel, minions, 3 ships and the theme in one pack.'],
    notes: xmasNote('open the "Bosses" tab at the top and buy "Christmas Pack". It unlocks everything above: the boss Noel, the Christmas minion looks, the 3 Christmas ships and the Christmas theme') },
);

const NOTES = 'This is a one-time (non-consumable) purchase. To test: tap the palette icon at the top left of the home screen to open "Customize & Shop", then buy this item. It becomes available to use right away. Use "Restore Purchases" at the bottom of the same screen to restore it. No account is required.';

const b = await chromium.connectOverCDP('http://127.0.0.1:9222');
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
  await waitFor('参照名', LIST);
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
  const label = `￥${yen.toLocaleString("en-US")}.00`;
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
