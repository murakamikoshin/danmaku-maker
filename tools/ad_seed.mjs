// 広告収録用(ci/ad-recording ブランチだけ): Firestore エミュレーターに、世界のステージのデモを入れる。
// 実行: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tools/ad_seed.mjs  (firebase/functions の node_modules を使う)
import { createRequire } from "node:module";
const require = createRequire(new URL("../firebase/functions/package.json", import.meta.url));
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
initializeApp({ projectId: "demo-danmaku" });
const db = getFirestore();

const EN = process.env.AD_LANG === "en";
const E = (t, x, y, i, c, v, r, k, extra = {}) => ({ t, x, y, s: 0, e: 180, i, c, v, r, k, ph: 0, ...extra });
const demo = [
  { name: EN ? "Twisted Galaxy" : "ねじれ銀河", author: "Sora", mode: "survive", d: 30, likes: 342, plays: 2104, clears: 391,
    em: [E("spiral", 0.5, 0.25, 0.08, 4, 1.9, 9, 3), E("ring", 0.5, 0.25, 1.1, 24, 1.6, 5, 1)] },
  { name: EN ? "Endless Rain" : "梅雨前線", author: EN ? "Ponzu" : "ぽんず", mode: "survive", d: 30, likes: 218, plays: 1530, clears: 702,
    em: [E("rain", 0.5, 0, 0.12, 3, 2.4, 0, 1), E("aim", 0.5, 0.1, 1.2, 3, 3, 24, 0)] },
  { name: EN ? "Pink Nightmare" : "ピンクの悪夢", author: "Mika", mode: "boss", d: 60, hp: 300, mv: 1, likes: 187, plays: 980, clears: 141,
    em: [E("ring", 0.5, 0.2, 0.6, 18, 2.1, 8, 0), E("aim", 0.5, 0.2, 0.9, 5, 2.8, 40, 0)] },
  { name: EN ? "Twin Vortex" : "双子の渦", author: EN ? "DanmakuSmith" : "だんまく職人", mode: "survive", d: 40, likes: 156, plays: 1210, clears: 233,
    em: [E("spiral", 0.3, 0.2, 0.1, 3, 1.8, 10, 1), E("spiral", 0.7, 0.2, 0.1, 3, 1.8, -10, 2)] },
  { name: EN ? "First-Try Killer" : "初見殺しの扇", author: "Leo", mode: "survive", d: 30, likes: 121, plays: 1650, clears: 98,
    em: [E("sweep", 0.5, 0.1, 0.12, 5, 2.8, 70, 4), E("ring", 0.2, 0.3, 0.9, 14, 2, 6, 3), E("ring", 0.8, 0.3, 0.9, 14, 2, -6, 3)] },
  { name: EN ? "Night Fireworks" : "夜空の花火", author: "hana", mode: "survive", d: 30, likes: 97, plays: 640, clears: 288,
    em: [E("ring", 0.3, 0.2, 0.8, 20, 2.1, 7, 2), E("ring", 0.7, 0.2, 0.8, 20, 2.1, -7, 0)] },
  { name: EN ? "Round and Round" : "回る回る", author: EN ? "Takumi" : "たくみ", mode: "survive", d: 20, likes: 64, plays: 410, clears: 230,
    em: [E("spiral", 0.5, 0.3, 0.09, 5, 1.7, 7, 4)] },
  { name: EN ? "I See You..." : "見てるぞ…", author: "Nao", mode: "survive", d: 30, likes: 41, plays: 302, clears: 120,
    em: [E("aim", 0.2, 0.15, 0.8, 5, 3, 36, 0), E("aim", 0.8, 0.15, 0.8, 5, 3, 36, 3)] },
];

const now = Date.now();
let n = 0;
for (const s of demo) {
  const id = ["K7QM2", "R4XTB", "9HWNC", "P3ZDV", "M8GAE", "T5YJQ", "W2KRF", "B6NUH"][n];
  await db.doc(`stages/${id}`).set({
    authorUid: `demo-${n}`, authorName: s.author, name: s.name, mode: s.mode, durationSec: s.d,
    bossHp: s.hp ?? null, bossMove: s.mv ?? null, emitters: s.em, formatVersion: 1,
    nameKeys: [], ogImagePath: "", status: "published",
    plays: s.plays, clears: s.clears, likes: s.likes, comments: Math.round(s.likes / 9), reports: 0,
    clearRate: s.clears / s.plays, hardRate: s.clears / s.plays, trending: s.likes * 3, trendUpdatedAt: now,
    // 新着順で、収録中に投稿するステージが一番上に来るように、デモは少し前の時刻にする
    createdAt: Timestamp.fromMillis(now - (n + 1) * 37 * 60 * 1000), lang: EN ? "en" : "ja",
  });
  n++;
}
console.log(`seeded ${n} demo stages`);
