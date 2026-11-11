import { randomInt, randomUUID } from "node:crypto";
import { getDatabaseWithUrl } from "firebase-admin/database";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { createSim, decodeReplay, mulberry } from "./fullsim.js";
import { RANKED_DURATION, rankedCompare, rankedScore, rankedStage, rankOf, ratingDelta, RATING_START, type RankedScore } from "./ranked.js";
import { namesFor } from "./rankednames.js";

/**
 * ランク戦(リアルタイム対戦)のサーバー処理。仕様書「ランク戦 仕様書(リアルタイム対戦)」。
 *
 * Realtime Database(速い通信用):
 * - rq/{uid}: 相手を待っている人 { r: レート, at: 待ち始めた時刻, m?: 決まった対戦の ID }。書くのはサーバーだけ。本人だけ読める
 * - rm/{matchId}/meta: 対戦の情報 { seed, startAt, players: { uid: { name, rating, title? } } }。書くのはサーバーだけ
 * - rm/{matchId}/p/{uid}: 対戦中の自機の位置 { x, y, t, dead? }。本人だけ書ける。二人とも読める
 * Firestore(残すもの):
 * - rankedPlayers/{uid}: { rating, games, wins, losses, draws, best }
 * - rankedMatches/{id}: 対戦の記録と結果(二人とも読める)
 * - rankedRuns/{id}: 検証済みの人の記録(相手が見つからない人のボットの動きに使う)
 * - rankedBots/{week}_{i}: 自動で遊ぶボットの記録(週ごとに用意する)
 */
const db = (): Firestore => getFirestore();
export const RTDB_URL = "https://danmaku-maker-default-rtdb.asia-southeast1.firebasedatabase.app";
const rtdb = () => getDatabaseWithUrl(RTDB_URL);

/** 人を探す時間(アプリはこの時間が過ぎたらボットを頼む)と、待ち行列で古いとみなす時間 */
export const SEARCH_MS = 10_000;
const STALE_MS = 15_000;
/** マッチしてから始まるまで(3・2・1 を見せる) */
const START_DELAY_MS = 4_000;
/** 始まってから結果を出すまでの締め切り(180 秒 + 通信の余裕) */
const SUBMIT_DEADLINE_MS = (RANKED_DURATION + 60) * 1000;
/** 週ごとのステージの数 */
export const SEEDS_PER_WEEK = 20;
const MAX_STEPS = (RANKED_DURATION + 3) * 120 + 144;

// ---- 週ごとの種 ----

/** 日本時間の月曜 0 時で切り替わる週の番号 */
export function weekOf(now: number): number {
  const jst = now + 9 * 3600_000;
  // 1970-01-01 は木曜。月曜始まりにずらす
  return Math.floor((jst + 3 * 86_400_000) / (7 * 86_400_000));
}

/** その週の種(決まった計算で作るので、保存しなくても同じものが出る) */
export function weekSeeds(week: number): number[] {
  const rng = mulberry((Math.imul(week, 0x9e3779b1) ^ 0x5eed5eed) >>> 0);
  return Array.from({ length: SEEDS_PER_WEEK }, () => Math.floor(rng() * 2 ** 32) >>> 0);
}

// ---- 自動で遊ぶボット ----

const SPEEDS = [6, 14];
const DIRS: [number, number][] = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];
const MOVES: [number, number][] = [[0, 0], ...SPEEDS.flatMap((s) => DIRS.map(([x, y]) => [Math.round(x * s * (x && y ? 0.71 : 1)), Math.round(y * s * (x && y ? 0.71 : 1))] as [number, number]))];

/** 先読みで避け続けるボット。maxTicks まで、または当たるまで。動きは人が出せる速さに抑える */
export function botRun(seed: number, maxTicks: number, opts = { every: 4, horizon: 24 }): { moves: Int8Array; steps: number } {
  const sim = createSim(rankedStage(seed), "standard");
  const oc = (): string => sim.outcome;
  const moves = new Int8Array(Math.min(maxTicks, MAX_STEPS) * 2);
  let n = 0;
  const limit = Math.min(maxTicks, MAX_STEPS);
  while (n < limit && oc() === "playing") {
    const base = sim.snapshot();
    let best = -Infinity, bm = MOVES[0]!;
    for (const m of MOVES) {
      let survived = 0, minD2 = 1e9;
      for (let k = 0; k < opts.horizon; k++) {
        sim.step(m[0], m[1]);
        if (oc() === "hit") break;
        survived += 1;
        if (k % 4 === 3) {
          const p = sim.player;
          for (const b of sim.bullets) { const dx = b.x - p.x, dy = b.y - p.y; const d = dx * dx + dy * dy; if (d < minD2) minD2 = d; }
        }
        if (oc() === "cleared") { survived = opts.horizon; break; }
      }
      const p = sim.player;
      const score = survived * 1000 + Math.min(Math.sqrt(minD2), 60) * 4 - Math.abs(p.x - 180) * 0.05 - Math.abs(p.y - 460) * 0.03 - (m[0] === 0 && m[1] === 0 ? 0 : 0.5);
      if (score > best) { best = score; bm = m; }
      sim.restore(base);
    }
    for (let k = 0; k < opts.every && n < limit && oc() === "playing"; k++) {
      moves[n * 2] = bm[0]; moves[n * 2 + 1] = bm[1];
      sim.step(bm[0], bm[1]);
      n += 1;
    }
  }
  return { moves: moves.slice(0, n * 2), steps: n };
}

/** 記録を、アプリと同じ形(Base64 の (回数, dx, dy) の並び。先頭 0 = そのまま)に詰める */
export function encodeReplay(moves: Int8Array, steps: number): string {
  const out: number[] = [0];
  let i = 0;
  while (i < steps) {
    const dx = moves[i * 2]!, dy = moves[i * 2 + 1]!;
    let n = 1;
    while (n < 255 && i + n < steps && moves[(i + n) * 2] === dx && moves[(i + n) * 2 + 1] === dy) n++;
    out.push(n, dx & 0xff, dy & 0xff);
    i += n;
  }
  return Buffer.from(out).toString("base64");
}

/**
 * その週の種ごとに、強いボットの記録を作っておく(相手の強さは、この記録を途中で切って合わせる)。
 * 1 本に 20〜160 秒かかるので、決まった時間(budgetMs)で区切り、続きは次の回(1 時間ごと)にやる。来週の分も先に作る
 */
export async function prepareWeek(now: number, budgetMs = 420_000, log: (m: string) => void = () => {}) {
  const t0 = Date.now();
  for (const week of [weekOf(now), weekOf(now) + 1]) {
    const seeds = weekSeeds(week);
    for (let i = 0; i < seeds.length; i++) {
      if (Date.now() - t0 > budgetMs) return;
      const ref = db().doc(`rankedBots/${week}_${i}`);
      if ((await ref.get()).exists) continue;
      const r = botRun(seeds[i]!, MAX_STEPS);
      const sc = rankedScore(seeds[i]!, r.moves, r.steps);
      await ref.set({ week, seed: seeds[i], replay: encodeReplay(r.moves, r.steps), ticks: sc.ticks, grazes: sc.grazes, createdAt: now });
      log(`ranked bot ${week}_${i}: ${(sc.ticks / 120).toFixed(1)}s`);
    }
  }
}

// ---- 対戦相手の情報 ----

interface PlayerState { rating: number; games: number; wins: number; losses: number; draws: number; best: number }
const freshPlayer = (): PlayerState => ({ rating: RATING_START, games: 0, wins: 0, losses: 0, draws: 0, best: RATING_START });

async function playerOf(uid: string): Promise<PlayerState> {
  const s = await db().doc(`rankedPlayers/${uid}`).get();
  return s.exists ? { ...freshPlayer(), ...(s.data() as Partial<PlayerState>) } : freshPlayer();
}

async function profileOf(uid: string): Promise<{ name: string; title?: string }> {
  const [u, p] = await Promise.all([db().doc(`users/${uid}`).get(), db().doc(`publicProfiles/${uid}`).get()]);
  const name = (u.get("displayName") as string | undefined)?.trim() || "Player";
  const title = p.get("title") as string | undefined;
  return title ? { name, title } : { name };
}

/** 自分の今のレートとランク・戦績 */
export async function rankedStatus(uid: string) {
  const p = await playerOf(uid);
  return { ...p, rank: rankOf(p.rating) };
}

// ---- 相手を探す ----

interface QueueEntry { r: number; at: number; m?: string }

/** 待ち行列に入る。待っている人がいればその場でマッチする。{ matchId } が返れば対戦が決まった(無ければ、rq/{uid}/m を待つ) */
export async function rankedJoin(uid: string, now = Date.now()) {
  const me = await playerOf(uid);
  const newId = randomUUID().replace(/-/g, "").slice(0, 20);
  const pick: { other: string | null } = { other: null };
  const res = await rtdb().ref("rq").transaction((cur: Record<string, QueueEntry> | null) => {
    const q: Record<string, QueueEntry> = { ...(cur ?? {}) };
    pick.other = null;
    for (const [k, e] of Object.entries(q)) if (!e || (!e.m && e.at < now - STALE_MS) || (e.m && e.at < now - 60_000)) delete q[k];
    if (q[uid]?.m) return q;   // もう決まっている
    let best: string | null = null, bestGap = Infinity;
    for (const [k, e] of Object.entries(q)) {
      if (k === uid || e.m || e.at < now - SEARCH_MS - 2000) continue;
      const gap = Math.abs(e.r - me.rating);
      const allowed = 150 + 30 * Math.max(0, (now - e.at) / 1000);
      if (gap <= allowed && gap < bestGap) { best = k; bestGap = gap; }
    }
    if (best) {
      q[best] = { ...q[best]!, m: newId };
      q[uid] = { r: me.rating, at: now, m: newId };
      pick.other = best;
    } else q[uid] = { r: me.rating, at: q[uid]?.at ?? now };
    return q;
  });
  const after = res.snapshot.child(uid).val() as QueueEntry | null;
  if (!res.committed || !after) throw new HttpsError("aborted", "queue-busy");
  if (after.m && pick.other && after.m === newId) {
    await createLiveMatch(newId, [pick.other, uid], now);
    return { matchId: newId };
  }
  return after.m ? { matchId: after.m } : { waiting: true, searchMs: SEARCH_MS };
}

async function createLiveMatch(id: string, uids: [string, string], now: number) {
  const seeds = weekSeeds(weekOf(now));
  const seed = seeds[randomInt(0, seeds.length)]!;
  const startAt = now + START_DELAY_MS;
  const info = await Promise.all(uids.map(async (u) => ({ uid: u, ...(await profileOf(u)), rating: (await playerOf(u)).rating })));
  const players: Record<string, { name: string; rating: number; title?: string }> = {};
  for (const p of info) players[p.uid] = { name: p.name, rating: p.rating, ...(p.title ? { title: p.title } : {}) };
  await db().doc(`rankedMatches/${id}`).set({ kind: "live", players: uids, seed, startAt, status: "playing", info: players, results: {}, createdAt: now });
  await rtdb().ref(`rm/${id}/meta`).set({ seed, startAt, players });
}

/** 待つのをやめる(画面を閉じたとき) */
export async function rankedLeave(uid: string) {
  await rtdb().ref("rq").transaction((cur: Record<string, QueueEntry> | null) => {
    if (!cur || !cur[uid] || cur[uid]!.m) return cur;
    const q = { ...cur }; delete q[uid]; return q;
  });
  return { ok: true };
}

/**
 * 相手が見つからなかった: ボットを相手にする。もし直前に人とマッチしていたら、そちらを返す。
 * 相手の動きは、その種を人が遊んだ検証済みの記録(レートが近いもの)、無ければ自動のボットの記録を、強さに合わせた長さで切ったもの
 */
export async function rankedBot(uid: string, lang: unknown, now = Date.now()) {
  const live: { id: string | null } = { id: null };
  await rtdb().ref("rq").transaction((cur: Record<string, QueueEntry> | null) => {
    live.id = null;
    if (!cur || !cur[uid]) return cur;
    if (cur[uid]!.m) { live.id = cur[uid]!.m!; return cur; }
    const q = { ...cur }; delete q[uid]; return q;
  });
  if (live.id) return { matchId: live.id };

  const me = await playerOf(uid);
  const week = weekOf(now);
  const seeds = weekSeeds(week);
  const idx = randomInt(0, seeds.length);
  const seed = seeds[idx]!;
  const names = namesFor(lang);
  const oppRating = Math.max(600, me.rating + randomInt(-60, 61));

  // 人の記録(自分以外・レートが近い)を優先する
  let opp: { replay: string; ticks: number; grazes: number; name: string; title?: string };
  const runs = await db().collection("rankedRuns").where("seed", "==", seed).orderBy("createdAt", "desc").limit(40).get();
  const cands = runs.docs.map((d) => d.data()).filter((r) => r.uid !== uid).sort((a, b) => Math.abs(a.rating - me.rating) - Math.abs(b.rating - me.rating));
  if (cands.length > 0 && Math.abs(cands[0]!.rating - me.rating) <= 250) {
    const r = cands[0]!;
    opp = { replay: r.replay, ticks: r.ticks, grazes: r.grazes, name: names[randomInt(0, names.length)]! };
  } else {
    // 強さ: レートが高いほど長く生き残る。同じレートでも少しばらつかせる
    const target = Math.round(120 * Math.min(RANKED_DURATION, Math.max(12, 25 + (oppRating - 800) * 0.12 + randomInt(-8, 9))));
    const bot = await db().doc(`rankedBots/${week}_${idx}`).get();
    // 週の記録がまだ無いときは、軽いボットでその長さだけ作る(保存しない)
    const full = bot.exists ? decodeReplay(bot.get("replay") as string, MAX_STEPS)! : botRun(seed, target, { every: 8, horizon: 16 });
    const steps = Math.min(full.steps, target);
    const sc = rankedScore(seed, full.moves, steps);
    opp = { replay: encodeReplay(full.moves, steps), ticks: sc.ticks, grazes: sc.grazes, name: names[randomInt(0, names.length)]! };
  }
  const id = randomUUID().replace(/-/g, "").slice(0, 20);
  const startAt = now + START_DELAY_MS;
  await db().doc(`rankedMatches/${id}`).set({
    kind: "bot", players: [uid], seed, startAt, status: "playing", results: {}, createdAt: now,
    opp: { name: opp.name, rating: oppRating, ticks: opp.ticks, grazes: opp.grazes },
  });
  return { matchId: id, seed, startAt, opponent: { name: opp.name, rating: oppRating, rank: rankOf(oppRating) }, replay: opp.replay };
}

// ---- 結果 ----

/** 自分の記録を送る。サーバーが計算し直して、勝ち負けが決まれば結果を返す(人同士で相手がまだなら pending) */
export async function rankedSubmit(uid: string, data: unknown, now = Date.now()) {
  const matchId = (data as { matchId?: unknown })?.matchId;
  const replay = (data as { replay?: unknown })?.replay;
  if (typeof matchId !== "string" || matchId.length < 8 || matchId.length > 40) throw new HttpsError("invalid-argument", "matchId");
  if (typeof replay !== "string" || replay.length > 200_000) throw new HttpsError("invalid-argument", "replay");
  const ref = db().doc(`rankedMatches/${matchId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "match");
  const m = snap.data()!;
  if (!(m.players as string[]).includes(uid)) throw new HttpsError("permission-denied", "not-player");
  if (m.status !== "playing") return resultFor(uid, m);
  if (now > (m.startAt as number) + SUBMIT_DEADLINE_MS) throw new HttpsError("deadline-exceeded", "late");
  const d = decodeReplay(replay, MAX_STEPS);
  if (!d) throw new HttpsError("invalid-argument", "replay-broken");
  const sc = rankedScore(m.seed as number, d.moves, d.steps);
  // 実際に遊んだ時間より早くは送れない(少しの余裕を見る)
  if (now < (m.startAt as number) + (sc.ticks / 120) * 1000 - 5000) throw new HttpsError("failed-precondition", "too-early");

  const final = await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data()!;
    if (cur.status !== "playing") return cur;
    const results = { ...(cur.results as Record<string, RankedScore>), [uid]: sc };
    if (cur.kind === "live" && Object.keys(results).length < 2) {
      tx.update(ref, { [`results.${uid}`]: sc });
      return { ...cur, results };
    }
    return finalize(tx, ref, { ...cur, results }, now);
  });
  if (sc.ticks >= 600) {
    const prof = await profileOf(uid);
    const me = await playerOf(uid);
    await db().collection("rankedRuns").add({ seed: m.seed, uid, name: prof.name, rating: me.rating, replay, ticks: sc.ticks, grazes: sc.grazes, createdAt: now });
  }
  return resultFor(uid, final);
}

type Tx = FirebaseFirestore.Transaction;
type DocRef = FirebaseFirestore.DocumentReference;

/** 勝ち負けを決めて、レートを動かす(トランザクションの中で呼ぶ)。来なかった人は 0 秒の扱い */
async function finalize(tx: Tx, ref: DocRef, m: FirebaseFirestore.DocumentData, now: number) {
  const players = m.players as string[];
  const results = m.results as Record<string, RankedScore>;
  const refs = players.map((u) => db().doc(`rankedPlayers/${u}`));
  const states = await Promise.all(refs.map(async (r) => { const s = await tx.get(r); return s.exists ? { ...freshPlayer(), ...(s.data() as Partial<PlayerState>) } : freshPlayer(); }));
  const scoreOf = (u: string): RankedScore => results[u] ?? { ticks: 0, grazes: 0 };
  const changes: Record<string, { before: number; after: number; result: 1 | 0.5 | 0 }> = {};
  if (m.kind === "bot") {
    const u = players[0]!;
    const c = rankedCompare(scoreOf(u), { ticks: m.opp.ticks, grazes: m.opp.grazes });
    const result = c > 0 ? 1 : c === 0 ? 0.5 : 0;
    const d = ratingDelta(states[0]!.rating, m.opp.rating, result, states[0]!.games, true);
    changes[u] = { before: states[0]!.rating, after: states[0]!.rating + d, result };
  } else {
    const [a, b] = players as [string, string];
    const c = rankedCompare(scoreOf(a), scoreOf(b));
    const ra = c > 0 ? 1 : c === 0 ? 0.5 : 0;
    const rb = (1 - ra) as 1 | 0.5 | 0;
    changes[a] = { before: states[0]!.rating, after: states[0]!.rating + ratingDelta(states[0]!.rating, states[1]!.rating, ra, states[0]!.games, false), result: ra };
    changes[b] = { before: states[1]!.rating, after: states[1]!.rating + ratingDelta(states[1]!.rating, states[0]!.rating, rb, states[1]!.games, false), result: rb };
  }
  players.forEach((u, i) => {
    const s = states[i]!, ch = changes[u]!;
    tx.set(refs[i]!, {
      rating: ch.after, games: s.games + 1, best: Math.max(s.best, ch.after),
      wins: s.wins + (ch.result === 1 ? 1 : 0), losses: s.losses + (ch.result === 0 ? 1 : 0), draws: s.draws + (ch.result === 0.5 ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  const done = { status: "done", results, changes, finishedAt: now };
  tx.update(ref, done);
  return { ...m, ...done };
}

function resultFor(uid: string, m: FirebaseFirestore.DocumentData) {
  const results = (m.results ?? {}) as Record<string, RankedScore>;
  const me = results[uid] ?? null;
  if (m.status !== "done") return { pending: true, me };
  const ch = (m.changes as Record<string, { before: number; after: number; result: number }>)[uid]!;
  const opp = m.kind === "bot" ? { ticks: m.opp.ticks, grazes: m.opp.grazes } : results[(m.players as string[]).find((u) => u !== uid)!] ?? { ticks: 0, grazes: 0 };
  return { pending: false, result: ch.result === 1 ? "win" : ch.result === 0 ? "lose" : "draw", me, opp, ratingBefore: ch.before, ratingAfter: ch.after, rank: rankOf(ch.after) };
}

/** 締め切りを過ぎた人同士の対戦を締める(来なかった人は負け)。古い通信用のデータも消す */
export async function sweepRanked(now = Date.now()) {
  const old = await db().collection("rankedMatches").where("status", "==", "playing").where("startAt", "<", now - SUBMIT_DEADLINE_MS).limit(100).get();
  for (const d of old.docs) {
    await db().runTransaction(async (tx) => {
      const cur = (await tx.get(d.ref)).data()!;
      if (cur.status !== "playing") return;
      await finalize(tx, d.ref, cur, now);
    });
  }
  const rooms = await rtdb().ref("rm").get();
  const del: Record<string, null> = {};
  rooms.forEach((c) => { const s = c.child("meta/startAt").val() as number | null; if (!s || s < now - 10 * 60_000) del[c.key!] = null; });
  if (Object.keys(del).length) await rtdb().ref("rm").update(del);
  return { closed: old.size, roomsRemoved: Object.keys(del).length };
}
