// サーバーから配る商品(ショップの「新着」)を、Firestore の catalog/shop に書く。アプリの更新も、審査もいらない。
// 使い方: GOOGLE_APPLICATION_CREDENTIALS=<管理者の鍵> node tools/publish_catalog.mjs   (鍵は Firebase コンソールで作り、このリポジトリには置かない)
//
// tools/catalog/shop.src.json の形:
//   { "v": 1, "items": [ {
//       "id": "x_newship_gold",                      // x_ で始まる小文字・数字・_ (28文字まで)
//       "kind": "ship",                              // いまは ship(ドット絵の自機)だけ
//       "name": { "ja": "ニュー・ゴールド", "en": "New Gold", ... },
//       "free": true,                                // 無料なら true。有料なら "productId": "com.koshin.danmakumaker.…"(ASC と RevenueCat に商品が要る)
//       "frames": ["art/rewards/…/…_0.png", "…_1.png", "…_2.png"],   // 32×32 の透過 PNG。3〜8コマ
//       "order": [0, 1, 2, 1]                         // 再生する順(省略すると 0,1,2…)
//   } ] }
// 絵や数値のデータだけを配る(動きを変えるプログラムは配らない)。アプリ側でも、形と大きさを確かめて、使えるものだけ出す。
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(new URL("../firebase/functions/package.json", import.meta.url));
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

const root = path.resolve(new URL("..", import.meta.url).pathname);
const src = JSON.parse(fs.readFileSync(path.join(root, "tools/catalog/shop.src.json"), "utf8"));
const items = src.items.map((it) => {
  if (!/^x_[a-z0-9_]{1,25}$/.test(it.id)) throw new Error(`id が不正: ${it.id}`);
  if (it.kind !== "ship") throw new Error(`kind が不正: ${it.id}`);
  if (!it.free && !String(it.productId || "").startsWith("com.koshin.danmakumaker.")) throw new Error(`有料の商品は productId が要る: ${it.id}`);
  const frames = it.frames.map((f) => fs.readFileSync(path.join(root, f)).toString("base64"));
  if (frames.length < 3 || frames.length > 8) throw new Error(`コマ数は3〜8: ${it.id}`);
  return { id: it.id, kind: it.kind, name: it.name, ...(it.free ? { free: true } : { productId: it.productId }), frames, ...(it.order ? { order: it.order } : {}) };
});
const doc = { v: 1, items };
const bytes = Buffer.byteLength(JSON.stringify(doc));
if (bytes > 900_000) throw new Error(`大きすぎます(${bytes} バイト)。Firestore の文書は 1MB まで`);
initializeApp({ credential: applicationDefault(), projectId: "danmaku-maker" });
await getFirestore().doc("catalog/shop").set(doc);
console.log(`書きました: ${items.length} 件(${bytes} バイト)`);
process.exit(0);
