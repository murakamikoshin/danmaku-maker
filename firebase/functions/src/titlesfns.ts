import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { awardsFor, competitionRanks, isTitleId, previousMonthId, scoreTitlesFor, monthIdJst, monthlyTitleId } from "./titles.js";

/**
 * 称号のサーバー処理。アプリからは付けさせない(付与は、検証済みの点数と、月の集計だけ)。
 *
 * - titleState/{uid}: 本人だけ読める。{ titles: 持っている称号の ID(スコア達成・週間とも永久), sel: 付けている称号(null=付けない。項目なし=まだ選んでいない) }
 * - publicProfiles/{uid}: ログイン済みなら誰でも読める。名前の横に出す分だけ。{ title, crown(1〜3), medal, cw(王冠・メダルの月) }
 * - swipeMonthly/{週}/scores/{uid}: 月ごとの自己ベスト(累計の swipeScores とは別)
 * - swipeMonthlyAwards/{週}: 集計の印(二重に配らない)
 */

/** 検証済みの点数で、スコア達成の称号を付ける。新しくもらった称号の ID を返す。まだ称号を選んだことがなければ、いちばん高いものを付ける */
export async function grantScoreTitles(db: Firestore, uid: string, score: bigint): Promise<string[]> {
  const ids = scoreTitlesFor(score);
  if (ids.length === 0) return [];
  const stateRef = db.doc(`titleState/${uid}`);
  const profileRef = db.doc(`publicProfiles/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(stateRef);
    const owned = (snap.get("titles") as string[] | undefined) ?? [];
    const fresh = ids.filter((id) => !owned.includes(id));
    if (fresh.length === 0) return [];
    const patch: Record<string, unknown> = { titles: [...owned, ...fresh] };
    if (snap.get("sel") === undefined) {
      const best = fresh[fresh.length - 1]!;
      patch.sel = best;
      tx.set(profileRef, { title: best }, { merge: true });
    }
    tx.set(stateRef, patch, { merge: true });
    return fresh;
  });
}

/** 称号を付ける(null で外す)。持っている称号だけ */
export async function setTitle(db: Firestore, uid: string, id: unknown): Promise<{ sel: string | null }> {
  if (id !== null && !isTitleId(id)) throw new HttpsError("invalid-argument", "title");
  const stateRef = db.doc(`titleState/${uid}`);
  const profileRef = db.doc(`publicProfiles/${uid}`);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(stateRef);
    const owned = (snap.get("titles") as string[] | undefined) ?? [];
    if (id !== null && !owned.includes(id)) throw new HttpsError("failed-precondition", "not-owned");
    tx.set(stateRef, { sel: id }, { merge: true });
    tx.set(profileRef, { title: id === null ? FieldValue.delete() : id }, { merge: true });
  });
  return { sel: id as string | null };
}

/** この月の自己ベストを残す(累計とは別。月が変わると、別の文書になる) */
export async function recordMonthlyBest(db: Firestore, month: string, uid: string, key: string, doc: Record<string, unknown>): Promise<void> {
  const ref = db.doc(`swipeMonthly/${month}/scores/${uid}`);
  await db.runTransaction(async (tx) => {
    const cur = await tx.get(ref);
    const curKey = cur.get("key") as string | undefined;
    if (curKey !== undefined && curKey >= key) { tx.update(ref, { a: doc.a, n: doc.n, num: doc.num, name: doc.name ?? FieldValue.delete() }); return; }
    tx.set(ref, { ...doc, key, createdAt: FieldValue.serverTimestamp() });
  });
}

export interface MonthlyAwardResult { month: string; participants: number; skipped?: boolean; cleared: number }

/**
 * 終わった月の順位から、月間の称号・王冠・メダルを配る(毎月 1 日 0:00 日本時間のあとに動く)。
 * 二重に配らない(印が done なら何もしない。途中で止まっていたら、30 分あとにやり直す。付与は何度やっても同じ結果)
 */
export async function runMonthlyAward(db: Firestore, nowMs: number): Promise<MonthlyAwardResult> {
  const month = previousMonthId(monthIdJst(nowMs));
  const marker = db.doc(`swipeMonthlyAwards/${month}`);
  const go = await db.runTransaction(async (tx) => {
    const m = await tx.get(marker);
    if (m.exists && (m.get("status") === "done" || nowMs - ((m.get("startedAt") as number | undefined) ?? 0) < 30 * 60_000)) return false;
    tx.set(marker, { status: "running", startedAt: nowMs });
    return true;
  });
  if (!go) return { month, participants: 0, skipped: true, cleared: 0 };

  // その月の記録を、点数の高い順に全部読む
  const entries: { uid: string; key: string }[] = [];
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = db.collection(`swipeMonthly/${month}/scores`).orderBy("key", "desc").limit(500);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    for (const d of page.docs) entries.push({ uid: d.id, key: d.get("key") as string });
    if (page.size < 500) break;
    last = page.docs[page.size - 1];
  }
  const ranks = competitionRanks(entries.map((e) => e.key));
  const total = entries.length;

  const bw = db.bulkWriter();
  bw.onWriteError((e) => e.failedAttempts < 5);
  entries.forEach((e, i) => {
    const a = awardsFor(ranks[i]!, total);
    if (a.kinds.length > 0) {
      bw.set(db.doc(`titleState/${e.uid}`), { titles: FieldValue.arrayUnion(...a.kinds.map((k) => monthlyTitleId(k, month))) }, { merge: true });
    }
    if (a.crown > 0 || a.medal) {
      bw.set(db.doc(`publicProfiles/${e.uid}`), { cw: month, ...(a.crown > 0 ? { crown: a.crown } : { crown: FieldValue.delete() }), ...(a.medal ? { medal: true } : { medal: FieldValue.delete() }) }, { merge: true });
    }
  });
  await bw.flush();

  // 先々月までの王冠・メダルを外す(称号そのものは永久に残る)
  let cleared = 0;
  for (;;) {
    const old = await db.collection("publicProfiles").where("cw", "!=", month).limit(500).get();
    if (old.empty) break;
    const cw = db.bulkWriter();
    for (const d of old.docs) cw.update(d.ref, { cw: FieldValue.delete(), crown: FieldValue.delete(), medal: FieldValue.delete() });
    await cw.close();
    cleared += old.size;
  }

  await marker.set({ status: "done", startedAt: nowMs, doneAt: Date.now(), participants: total, cleared });
  logger.info("swipe-monthly-award", { month, participants: total, cleared });
  return { month, participants: total, cleared };
}
