import type { Firestore } from "firebase-admin/firestore";

/** 「急上昇」の点数が半分になるまでの時間(2日) */
export const TREND_HALF_LIFE_MS = 2 * 24 * 3600 * 1000;

/** この点数を下回ったら 0 にして、以後の更新の対象から外す */
export const TREND_FLOOR = 0.5;

export const decay = (value: number, from: number, now: number) => value * 0.5 ** ((now - from) / TREND_HALF_LIFE_MS);

/**
 * 急上昇の点数を、いまの時刻まで減らして保存し直す。
 * 点数は、遊ばれたりいいねされたりしたときにしか減らないので、そのままだと、ずっと誰にも遊ばれていない昔の人気ステージが
 * 古い高い点数のまま一覧の上に残ってしまう。定期的にこれを呼んで、一覧の並び(保存されている点数の順)を新鮮に保つ。
 * 返すのは、更新したステージの数。
 */
export async function refreshTrending(db: Firestore, now: number, pageSize = 200): Promise<number> {
  let updated = 0;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = db.collection("stages").where("trending", ">", TREND_FLOOR).orderBy("trending").limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      await db.runTransaction(async (tx) => {
        const cur = await tx.get(doc.ref);
        const value = cur.get("trending");
        if (typeof value !== "number" || value <= TREND_FLOOR) return;   // 取得してから、ほかの更新で変わっていた
        const from = (cur.get("trendUpdatedAt") as number | undefined) ?? now;
        const next = decay(value, from, now);
        tx.update(doc.ref, { trending: next < TREND_FLOOR ? 0 : next, trendUpdatedAt: now });
      });
      updated++;
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return updated;
}
