import { randomInt } from "node:crypto";
import { FieldPath, FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { decodeReplay, type SimStage } from "./fullsim.js";
import { candidatesOf, estimatedClearRate, playRunAsync, rankingKey, type FeedEntry } from "./swipe.js";
import { botCanClear } from "./swipebot.js";
import { current, dayKeyJst, hasPass, refill, spend, type StaminaState } from "./stamina.js";
import { validateDisplayName } from "./validate.js";
import { GEN_AUTHOR, GEN_CLIP_AT, genId, generateStage, parseGenId } from "./swipegen.js";
import { GEN_SEEDS } from "./swipegen_seeds.js";

/** スワイプ弾幕のサーバー処理(仕様書 8〜16 章)。index.ts の onCall から呼ぶ */
const db = (): Firestore => getFirestore();
const RUN_TTL_MS = 3 * 3600_000;
const MAX_CLIPS = 200;
const CHUNK = 2000;
const HANDLE_CHOICES = 16;
export const DRINK_PRODUCT = "com.koshin.danmakumaker.stamina.drink";
export const PASS_PRODUCT = "com.koshin.danmakumaker.pass.stamina.monthly";

const isMemberToken = (token: { firebase?: { sign_in_provider?: string } } | undefined) => !!token && token.firebase?.sign_in_provider !== "anonymous";

function staminaOf(user: { get(f: string): unknown }): StaminaState | undefined {
  const s = user.get("stamina") as StaminaState | undefined;
  return s && typeof s.v === "number" && typeof s.at === "number" ? s : undefined;
}

async function staminaView(uid: string, now: number) {
  const user = await db().doc(`users/${uid}`).get();
  const unlimited = hasPass(user.get("pass") as { until?: number } | undefined, now);
  const cur = current(staminaOf(user), now);
  return { value: cur.value, nextAt: cur.nextAt, drinks: (user.get("drinks") as number | undefined) ?? 0, unlimited, adRefillUsed: user.get("adRefillDay") === dayKeyJst(now) };
}

export const getStamina = (uid: string) => staminaView(uid, Date.now());

/** プレイを始める: スタミナを 1 使い、その回の種(seed)と、使う候補の一覧の版を決める。無限スタミナのパスがあれば消費しない */
export async function useStamina(uid: string, data: unknown) {
  const author = (data as { author?: unknown })?.author;
  if (author !== undefined && author !== null && (typeof author !== "string" || author.length < 1 || author.length > 128)) throw new HttpsError("invalid-argument", "author");
  const meta = await db().doc("swipePools/meta").get();
  const version = meta.get("current") as string | undefined;
  if (!version) throw new HttpsError("failed-precondition", "pool-empty");

  const now = Date.now();
  const userRef = db().doc(`users/${uid}`);
  const seed = randomInt(0, 2 ** 32);
  const runRef = db().collection("swipeRuns").doc();
  await db().runTransaction(async (tx) => {
    const user = await tx.get(userRef);
    if (typeof author === "string" && ((user.get("blockedUids") as string[] | undefined) ?? []).includes(author)) throw new HttpsError("failed-precondition", "author-blocked");
    const unlimited = hasPass(user.get("pass") as { until?: number } | undefined, now);
    const base = user.exists ? {} : { displayName: "", postCount: 0, blockedUids: [], createdAt: FieldValue.serverTimestamp() };
    if (!unlimited) {
      const next = spend(staminaOf(user), now);
      if (!next) throw new HttpsError("resource-exhausted", "no-stamina");
      tx.set(userRef, { ...base, stamina: next }, { merge: true });
    } else if (!user.exists) tx.set(userRef, base, { merge: true });
    tx.set(runRef, { uid, seed, poolVersion: version, author: author ?? null, status: "open", createdAt: now });
  });
  return { runId: runRef.id, seed, poolVersion: version, ...(await staminaView(uid, now)) };
}

/** 広告を見たことを報告して、スタミナを全回復する(1 日 1 回) */
export async function refillByAd(uid: string) {
  const now = Date.now();
  const ref = db().doc(`users/${uid}`);
  await db().runTransaction(async (tx) => {
    const user = await tx.get(ref);
    const today = dayKeyJst(now);
    if (user.get("adRefillDay") === today) throw new HttpsError("resource-exhausted", "ad-refill-used");
    const base = user.exists ? {} : { displayName: "", postCount: 0, blockedUids: [], createdAt: FieldValue.serverTimestamp() };
    tx.set(ref, { ...base, stamina: refill(now), adRefillDay: today }, { merge: true });
  });
  return staminaView(uid, now);
}

/** 回復ドリンクを 1 本使って全回復する */
export async function useDrink(uid: string) {
  const now = Date.now();
  const ref = db().doc(`users/${uid}`);
  await db().runTransaction(async (tx) => {
    const user = await tx.get(ref);
    const drinks = (user.get("drinks") as number | undefined) ?? 0;
    if (drinks < 1) throw new HttpsError("failed-precondition", "no-drink");
    tx.update(ref, { drinks: drinks - 1, stamina: refill(now) });
  });
  return staminaView(uid, now);
}

// ---------- 候補の一覧 ----------
async function loadPool(version: string): Promise<FeedEntry[]> {
  const snap = await db().collection(`swipePools/${version}/chunks`).orderBy(FieldPath.documentId()).get();
  return snap.docs.flatMap((d) => (d.get("entries") as FeedEntry[]) ?? []);
}

/** ボットでクリアできると確かめたランダム生成のクリップを、毎日まとめる。古い版は 2 つ前まで残す */
export async function buildPool(): Promise<{ version: string; count: number }> {
  // スワイプ弾幕は、ランダム生成のステージだけを流す(世界のステージは混ぜない)。
  // 生成のステージは、ボットで実際にクリアできると確かめたものだけなので、避ける隙間がない場面は出ない
  const entries: FeedEntry[] = [];
  // ボットでクリアできると確かめたランダム生成ステージ(アプリにも同じ生成のしかたが入っている)
  for (const [seed, hard, d] of GEN_SEEDS) entries.push({ id: genId(seed, hard), d, author: GEN_AUTHOR });
  if (entries.length === 0) return { version: "", count: 0 };
  const version = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
  for (let i = 0; i * CHUNK < entries.length; i++) {
    await db().doc(`swipePools/${version}/chunks/${String(i).padStart(4, "0")}`).set({ entries: entries.slice(i * CHUNK, (i + 1) * CHUNK) });
  }
  await db().doc(`swipePools/${version}`).set({ count: entries.length, createdAt: Date.now() });
  await db().doc("swipePools/meta").set({ current: version, count: entries.length, updatedAt: Date.now() });
  // 古い版を消す(新しいほうから 3 つ残す)
  const all = (await db().collection("swipePools").select().get()).docs.map((d) => d.id).filter((id) => id !== "meta").sort().reverse();
  for (const old of all.slice(3)) {
    await db().recursiveDelete(db().doc(`swipePools/${old}`));
  }
  return { version, count: entries.length };
}

// ---------- クリップの検証 ----------
/** ステージのクリップを調べて保存する: 盛り上がっている順の区間を、ボットでクリアできたものが出るまで試す */
export async function checkClip(id: string, stage: SimStage): Promise<{ ok: boolean; at?: number }> {
  const cands = candidatesOf(stage);
  let found: { at: number; est: number } | undefined;
  for (const c of cands) {
    if (botCanClear(stage, c.at).ok) { found = { at: c.at, est: Math.round(estimatedClearRate(c.total / 20) * 1000) / 1000 }; break; }
  }
  await db().doc(`stages/${id}`).update({ clip: found ? { ok: true, at: found.at, est: found.est, checkedAt: Date.now() } : { ok: false, checkedAt: Date.now() } });
  return found ? { ok: true, at: found.at } : { ok: false };
}

/** クリップを調べていない公開ステージを、少しずつ調べる(既存のステージ用。新しい投稿は投稿時に調べる) */
export async function checkMissingClips(maxStages: number): Promise<number> {
  let done = 0;
  let last: string | undefined;
  while (done < maxStages) {
    let q = db().collection("stages").where("status", "==", "published").orderBy(FieldPath.documentId()).limit(300);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    for (const d of snap.docs) {
      if (done >= maxStages) break;
      if (d.get("clip") !== undefined) continue;
      try { await checkClip(d.id, d.data() as SimStage); } catch (e) { logger.error("clip-check-failed", { id: d.id, error: String(e) }); await d.ref.update({ clip: { ok: false, checkedAt: Date.now(), error: true } }); }
      done += 1;
    }
    if (snap.size < 300) break;
    last = snap.docs[snap.size - 1]!.id;
  }
  return done;
}

// ---------- 1 プレイの提出 ----------
interface ClipIn { go: string; moves: string; skipped: boolean }

function parseClips(raw: unknown): ClipIn[] {
  if (!Array.isArray(raw) || raw.length > MAX_CLIPS) throw new HttpsError("invalid-argument", "clips");
  return raw.map((c) => {
    const k = c as { go?: unknown; moves?: unknown; skipped?: unknown };
    const ok = (v: unknown) => typeof v === "string" && v.length <= 20_000 && (v === "" || /^[A-Za-z0-9+/]+={0,2}$/.test(v));
    if (!ok(k.go) || !ok(k.moves) || typeof k.skipped !== "boolean") throw new HttpsError("invalid-argument", "clip");
    return { go: k.go as string, moves: k.moves as string, skipped: k.skipped };
  });
}

/** 1 プレイを受け取り、サーバーが記録から点数を計算し直して、ランキング(ログイン済みの人だけ)に載せる */
export async function submitSwipeRun(uid: string, member: boolean, data: unknown) {
  const d = data as { runId?: unknown; clips?: unknown; handle?: { a?: unknown; n?: unknown }; name?: unknown };
  if (typeof d.runId !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(d.runId)) throw new HttpsError("invalid-argument", "run-id");
  const clips = parseClips(d.clips);
  const runRef = db().doc(`swipeRuns/${d.runId}`);
  const now = Date.now();
  const run = await db().runTransaction(async (tx) => {
    const snap = await tx.get(runRef);
    if (!snap.exists || snap.get("uid") !== uid) throw new HttpsError("not-found", "run");
    if (snap.get("status") !== "open") throw new HttpsError("failed-precondition", "run-closed");
    if (now - (snap.get("createdAt") as number) > RUN_TTL_MS) throw new HttpsError("failed-precondition", "run-expired");
    tx.update(runRef, { status: "done", doneAt: now });
    return snap.data()!;
  });

  const decoded = clips.map((c) => {
    const go = c.go === "" ? { moves: new Int8Array(0), steps: 0 } : decodeReplay(c.go, 60);
    const mv = c.moves === "" ? { moves: new Int8Array(0), steps: 0 } : decodeReplay(c.moves, 1200);
    if (!go || !mv) throw new HttpsError("invalid-argument", "replay");
    return { go: go.moves, goCount: go.steps, moves: mv.moves, moveCount: mv.steps, skipped: c.skipped };
  });

  const [pool, userSnap] = await Promise.all([loadPool(run.poolVersion as string), db().doc(`users/${uid}`).get()]);
  const author = run.author as string | null;
  const blocked = new Set<string>((userSnap.get("blockedUids") as string[] | undefined) ?? []);
  if (!author) blocked.add(uid);
  const usePool = author ? pool.filter((e) => e.author === author) : pool;

  const stageCache = new Map<string, { stage: SimStage; at: number } | null>();
  const result = await playRunAsync(run.seed as number, usePool, blocked, async (id) => {
    if (!stageCache.has(id)) {
      const gen = parseGenId(id);
      if (gen) { stageCache.set(id, { stage: generateStage(gen.seed, gen.hard), at: GEN_CLIP_AT }); return stageCache.get(id) ?? null; }
      const s = await db().doc(`stages/${id}`).get();
      stageCache.set(id, s.exists && typeof s.get("clip.at") === "number" ? { stage: s.data() as SimStage, at: s.get("clip.at") as number } : null);
    }
    return stageCache.get(id) ?? null;
  }, decoded);
  // 提出の記録を残す(アプリの計算とサーバーの計算がずれたときに、原因を追えるように)。クリップの数が合わないのは、サーバーが先に被弾などで終わった印
  const summary = { sent: clips.length, played: result.clipsPlayed, cleared: result.clipsCleared, bestStreak: result.bestStreak, endedByHit: result.endedByHit, invalid: result.invalid ?? null, ids: result.clipIDs.slice(-3) };
  if (result.invalid || result.clipsPlayed < clips.length) {
    logger.warn("swipe-submit-mismatch", summary);
    // 原因を後から再現できるよう、送られた記録をそのまま残す(失敗しても提出は続ける)。Firestore の 1 文書は約 1MB までなので、収まる分だけ
    try {
      const kept: ClipIn[] = [];
      let size = 0;
      for (const c of clips) {
        size += c.go.length + c.moves.length + 40;
        if (size > 800_000) break;
        kept.push(c);
      }
      await db().doc(`swipeMismatches/${d.runId}`).set({
        uid, runId: d.runId, seed: run.seed, poolVersion: run.poolVersion, author: author ?? null,
        sent: clips.length, kept: kept.length, summary, clipIDs: result.clipIDs, clipOutcomes: result.clipOutcomes,
        scoreAfterEachClip: result.scoreAfterEachClip, clips: kept, createdAt: FieldValue.serverTimestamp(),
      });
    } catch (e) { logger.error("swipe-mismatch-save-failed", { message: String(e) }); }
  } else logger.info("swipe-submit", summary);
  if (result.invalid) {
    if (result.invalid === "pool-exhausted" && result.clipsPlayed > 0) { /* 全部遊び切った: ここまでの点数でよい */ } else throw new HttpsError("invalid-argument", result.invalid);
  }

  // クリップごとの挑戦数・クリア数(クリア率の実測)。スキップは数えない
  const stat = new Map<string, { plays: number; clears: number }>();
  result.clipIDs.forEach((id, i) => {
    if (parseGenId(id)) return;   // 生成したものは、挑戦数を数えない
    const o = result.clipOutcomes[i];
    if (o === "skipped" || o === "abandoned") return;
    const cur = stat.get(id) ?? { plays: 0, clears: 0 };
    cur.plays += 1;
    if (o === "cleared") cur.clears += 1;
    stat.set(id, cur);
  });
  for (const [id, s] of stat) {
    await db().doc(`stages/${id}`).update({ clipPlays: FieldValue.increment(s.plays), clipClears: FieldValue.increment(s.clears) }).catch(() => undefined);
  }

  // ランキング: ログイン済みで、作者で絞っていないプレイだけ。自己ベストだけ残す
  let ranked = false, improved = false;
  if (member && !author && result.score > 0n) {
    const a = d.handle?.a, n = d.handle?.n;
    if (!Number.isInteger(a) || !Number.isInteger(n) || (a as number) < 0 || (a as number) >= HANDLE_CHOICES || (n as number) < 0 || (n as number) >= HANDLE_CHOICES) throw new HttpsError("invalid-argument", "handle");
    const dn = validateDisplayName(d.name);
    // 名前が使えないとき(長すぎ・NGワード)は、提出を失敗させず、匿名の名前で載せる
    const shownName = dn.ok ? dn.name : undefined;
    ranked = true;
    const key = rankingKey(result.score);
    const ref = db().doc(`swipeScores/${uid}`);
    improved = await db().runTransaction(async (tx) => {
      const cur = await tx.get(ref);
      const curKey = cur.get("key") as string | undefined;
      const look = { a, n, num: handleNumber(uid), name: shownName ?? FieldValue.delete() };
      if (curKey !== undefined && curKey >= key) { tx.update(ref, look); return false; }
      tx.set(ref, { uid, key, score: result.score.toString(), bestStreak: result.bestStreak, clips: result.clipsCleared, a, n, num: handleNumber(uid), ...(shownName ? { name: shownName } : {}), createdAt: FieldValue.serverTimestamp() });
      return true;
    });
  }
  return {
    score: result.score.toString(), clipsCleared: result.clipsCleared, bestStreak: result.bestStreak, bombs: result.bombs, grazes: result.grazes,
    endedByHit: result.endedByHit, scoreAfterEachClip: result.scoreAfterEachClip, ranked, improved,
  };
}

function handleNumber(uid: string): number {
  let h = 2166136261;
  for (const ch of uid) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
  return h % 10000;
}

/** 上位 100 件と、自分の順位 */
export async function swipeRanking(uid: string) {
  const top = await db().collection("swipeScores").orderBy("key", "desc").limit(100).get();
  const rows = top.docs.map((d, i) => ({ rank: i + 1, uid: d.id === uid ? d.id : undefined, mine: d.id === uid, score: d.get("score") as string, bestStreak: d.get("bestStreak") as number, a: d.get("a") as number, n: d.get("n") as number, num: d.get("num") as number, name: (d.get("name") as string | undefined) ?? null }));
  const mine = await db().doc(`swipeScores/${uid}`).get();
  let my: { rank: number; score: string; bestStreak: number } | null = null;
  if (mine.exists) {
    const ahead = await db().collection("swipeScores").where("key", ">", mine.get("key")).count().get();
    my = { rank: ahead.data().count + 1, score: mine.get("score") as string, bestStreak: mine.get("bestStreak") as number };
  }
  return { rows, my };
}

// ---------- 課金の通知(RevenueCat) ----------
export async function applyPurchaseEvent(event: { id?: string; type?: string; app_user_id?: string; product_id?: string; expiration_at_ms?: number | null }): Promise<string> {
  const { id, type, app_user_id: uid, product_id: product } = event;
  if (!id || !type || !uid || !product) return "ignored";
  if (uid.startsWith("$RCAnonymousID")) return "anonymous";
  const evRef = db().doc(`swipeEvents/${id}`);
  const userRef = db().doc(`users/${uid}`);
  return db().runTransaction(async (tx) => {
    if ((await tx.get(evRef)).exists) return "duplicate";
    const base = { displayName: "", postCount: 0, blockedUids: [], createdAt: FieldValue.serverTimestamp() };
    const user = await tx.get(userRef);
    let outcome = "ignored";
    if (product === DRINK_PRODUCT && (type === "NON_RENEWING_PURCHASE" || type === "INITIAL_PURCHASE")) {
      tx.set(userRef, { ...(user.exists ? {} : base), drinks: FieldValue.increment(1) }, { merge: true });
      outcome = "drink";
    } else if (product === PASS_PRODUCT) {
      const until = event.expiration_at_ms ?? 0;
      if (["INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION", "NON_RENEWING_PURCHASE"].includes(type)) {
        tx.set(userRef, { ...(user.exists ? {} : base), pass: { until } }, { merge: true });
        outcome = "pass";
      } else if (type === "EXPIRATION") {
        tx.set(userRef, { ...(user.exists ? {} : base), pass: { until: Math.min(until || Date.now(), Date.now()) } }, { merge: true });
        outcome = "pass-expired";
      }
    }
    tx.set(evRef, { type, uid, product, outcome, createdAt: Date.now() });
    return outcome;
  });
}

export { isMemberToken };
