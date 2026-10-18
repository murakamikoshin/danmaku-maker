import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

export const STAGE_ID = "K7X2P";

/** エミュレーターのFirestoreに、テスト用のステージを1つ入れる */
export default async function globalSetup() {
  process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
  const app = initializeApp({ projectId: "demo-danmaku" }, "seed");
  const db = getFirestore(app);
  const base = {
    authorUid: "seed-author", authorName: "Koshin", mode: "survive", durationSec: 20, bossHp: null, bossMove: null,
    ogImagePath: "", formatVersion: 1, status: "published", plays: 20, clears: 7, likes: 3, reports: 0, createdAt: new Date(), lang: "ja",
    emitters: [
      { t: "spiral", x: 0.5, y: 0.25, s: 0, e: 20, i: 0.12, c: 3, v: 1.8, r: 11, k: 1, ph: 0 },
      { t: "aim", x: 0.5, y: 0.15, s: 2, e: 20, i: 0.9, c: 5, v: 3, r: 40, k: 3, ph: 0 },
    ],
  };
  await db.doc(`stages/${STAGE_ID}`).set({ ...base, name: "地獄の渦 <script>x</script>" });
  await db.doc("stages/HIDD3").set({ ...base, name: "非公開ステージ", status: "hidden" });
}
