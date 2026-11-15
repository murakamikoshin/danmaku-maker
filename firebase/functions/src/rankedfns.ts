import { createHmac, randomInt, randomUUID } from "node:crypto";
import { getDatabaseWithUrl } from "firebase-admin/database";
import { FieldValue, getFirestore, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { createSim, decodeReplay, mulberry } from "./fullsim.js";
import { RANKED_DURATION, rankedCompare, rankedScore, rankedStage, rankOf, ratingDelta, RATING_START, type RankedScore } from "./ranked.js";
import { namesFor } from "./rankednames.js";
import { pairKey, PAIR_RATED_PER_DAY } from "./abuse.js";
import { validateDisplayName } from "./validate.js";

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
 * - rankedMeta/{uid}: { lastSubmitAt(記録を最後に出した時刻), lastBotAt(ボット戦を最後に頼んだ時刻), bot(遊んでいる途中のボット戦の ID) }。サーバーだけ
 * - rankedPairs/{uid1}_{uid2}_{日}: 同じ二人が、その日に対戦した数 { n, at }。サーバーだけ
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
/** 記録の文字数の上限。圧縮しない形で 1 ステップごとに向きを変えても 88,420 文字に収まる */
export const MAX_RANKED_REPLAY = 90_000;
/** 記録を出す間隔(これより早い 2 回目は断る) */
const SUBMIT_INTERVAL_MS = 3_000;
/** ボット戦を頼む間隔(これより早い 2 回目は断る) */
export const BOT_INTERVAL_MS = 5_000;
/** 相手の位置の更新がこれだけ止まっていたら(または一度も届かないまま、これだけ過ぎたら)、相手はいなくなったとみなす */
export const GONE_GRACE_MS = 30_000;
/** 相手の位置(遊んだステップ数)が、始まってからの時間よりこれ以上遅れていたら、いなくなったとみなす(遅い端末の遅れより長く) */
export const GONE_LAG_MS = 75_000;
/** 人の記録(rankedRuns)を残す日数。種は週ごとに変わるので、古いものは使わない */
const RUN_KEEP_MS = 14 * 86_400_000;

// ---- 週ごとの種 ----

/** 日本時間の月曜 0 時で切り替わる週の番号 */
export function weekOf(now: number): number {
  const jst = now + 9 * 3600_000;
  // 1970-01-01 は木曜。月曜始まりにずらす
  return Math.floor((jst + 3 * 86_400_000) / (7 * 86_400_000));
}

/**
 * その週の種(決まった計算で作るので、保存しなくても同じものが出る)。
 * サーバーだけが知る合言葉(環境変数 RANKED_SEED_SALT)を混ぜて、リポジトリの計算から先の週のステージを作って練習できないようにする。
 * 合言葉が無いときは、これまでどおりの計算(公開されているので、先読みはできてしまう)
 */
export function weekSeeds(week: number, salt: string = process.env.RANKED_SEED_SALT ?? ""): number[] {
  const base = salt
    ? createHmac("sha256", salt).update(`ranked-week-${week}`).digest().readUInt32BE(0)
    : (Math.imul(week, 0x9e3779b1) ^ 0x5eed5eed) >>> 0;
  const rng = mulberry(base);
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
      // 合言葉を変えると種も変わるので、種の違う古い記録は作り直す
      const cur = await ref.get();
      if (cur.exists && cur.get("seed") === seeds[i]) continue;
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

/** 相手に見せる名前。NGワードの検査を通らない名前(古いデータなど)は出さず、"Player" にする */
export function safeName(raw: unknown): string {
  const v = validateDisplayName(raw);
  return v.ok && v.name ? v.name : "Player";
}

async function profileOf(uid: string): Promise<{ name: string; title?: string }> {
  const [u, p] = await Promise.all([db().doc(`users/${uid}`).get(), db().doc(`publicProfiles/${uid}`).get()]);
  const name = safeName(u.get("displayName"));
  const title = p.get("title") as string | undefined;
  return title ? { name, title } : { name };
}

/** 自分の今のレートとランク・戦績 */
export async function rankedStatus(uid: string) {
  const p = await playerOf(uid);
  return { ...p, rank: rankOf(p.rating) };
}

// ---- 相手を探す ----

/** s: 決まった対戦の始まる時刻。始まったあとは、その行を使わない(消す) */
interface QueueEntry { r: number; at: number; m?: string; s?: number }

/** 待ち行列の行が、もう要らないか(長く待ちすぎ・決まった対戦がもう始まった) */
export function queueRowExpired(e: QueueEntry | null | undefined, now: number): boolean {
  if (!e) return true;
  if (!e.m) return e.at < now - STALE_MS;
  return (e.s ?? e.at + START_DELAY_MS) <= now;
}

/** 待ち行列に入る。待っている人がいればその場でマッチする。{ matchId } が返れば対戦が決まった(無ければ、rq/{uid}/m を待つ) */
export async function rankedJoin(uid: string, now = Date.now()) {
  // 終わっていないボット戦があれば、先に負けで締める(レートも、そのあとの値で探す)
  await settleOpenBot(uid, now);
  const me = await playerOf(uid);
  const newId = randomUUID().replace(/-/g, "").slice(0, 20);
  const pick: { other: string | null } = { other: null };
  const res = await rtdb().ref("rq").transaction((cur: Record<string, QueueEntry> | null) => {
    const q: Record<string, QueueEntry> = { ...(cur ?? {}) };
    pick.other = null;
    // 古い行と、決まった対戦がもう始まった行は消す(始まった対戦には、もう入れない)
    for (const [k, e] of Object.entries(q)) if (queueRowExpired(e, now)) delete q[k];
    if (q[uid]?.m) return q;   // もう決まっている(まだ始まっていない)
    let best: string | null = null, bestGap = Infinity;
    for (const [k, e] of Object.entries(q)) {
      if (k === uid || e.m || e.at < now - SEARCH_MS - 2000) continue;
      const gap = Math.abs(e.r - me.rating);
      const allowed = 150 + 30 * Math.max(0, (now - e.at) / 1000);
      if (gap <= allowed && gap < bestGap) { best = k; bestGap = gap; }
    }
    if (best) {
      q[best] = { ...q[best]!, m: newId, s: now + START_DELAY_MS };
      q[uid] = { r: me.rating, at: now, m: newId, s: now + START_DELAY_MS };
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
  // 先に待っていた人は rq/{uid}/m を見て対戦を知るので、行は始まる時刻まで残す(始まったら、次に誰かが入るときに消える)
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
 * ボット戦は 1 人 1 つまで。前のボット戦が終わっていなければ、始まる前でも負け(来なかった扱い = 0 秒)で締める。
 * 返したボットの記録(相手の強さ)を見てから、取り消して引き直せないように(rankedStartBot・rankedJoinQueue の初めに呼ぶ)
 */
async function settleOpenBot(uid: string, now: number) {
  const prevId = (await db().doc(`rankedMeta/${uid}`).get()).get("bot") as string | undefined;
  if (!prevId) return;
  const prevRef = db().doc(`rankedMatches/${prevId}`);
  await db().runTransaction(async (tx) => {
    const prev = await tx.get(prevRef);
    if (!prev.exists || prev.get("status") !== "playing") return;
    await finalize(tx, prevRef, prev.data()!, now);
  });
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
    // まだ始まっていない人との対戦が決まっていれば、そちらへ。始まってしまった対戦には戻さない
    if (cur[uid]!.m && !queueRowExpired(cur[uid], now)) { live.id = cur[uid]!.m!; return cur; }
    const q = { ...cur }; delete q[uid]; return q;
  });
  if (live.id) return { matchId: live.id };

  // ボット戦を続けて頼むのを防ぐ(相手の記録を見てから引き直して、弱い相手を選ぶのを防ぐ。前のボット戦は下で負けになる)
  const metaRef = db().doc(`rankedMeta/${uid}`);
  await db().runTransaction(async (tx) => {
    const last = ((await tx.get(metaRef)).get("lastBotAt") as number | undefined) ?? 0;
    if (now - last < BOT_INTERVAL_MS && now >= last) throw new HttpsError("resource-exhausted", "too-fast");
    tx.set(metaRef, { lastBotAt: now }, { merge: true });
  });
  await settleOpenBot(uid, now);

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
    // 週の記録がまだ無い(または、合言葉を変える前の種の記録)ときは、軽いボットでその長さだけ作る(保存しない)
    const stored = bot.exists && bot.get("seed") === seed ? decodeReplay(bot.get("replay") as string, MAX_STEPS) : null;
    const full = stored ?? botRun(seed, target, { every: 8, horizon: 16 });
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
  await metaRef.set({ bot: id }, { merge: true });
  return { matchId: id, seed, startAt, opponent: { name: opp.name, rating: oppRating, rank: rankOf(oppRating) }, replay: opp.replay };
}

// ---- 結果 ----

/** 自分の記録を送る。サーバーが計算し直して、勝ち負けが決まれば結果を返す(人同士で相手がまだなら pending) */
export async function rankedSubmit(uid: string, data: unknown, now = Date.now()) {
  const matchId = (data as { matchId?: unknown })?.matchId;
  const replay = (data as { replay?: unknown })?.replay;
  if (typeof matchId !== "string" || matchId.length < 8 || matchId.length > 40) throw new HttpsError("invalid-argument", "matchId");
  if (typeof replay !== "string" || replay.length > MAX_RANKED_REPLAY) throw new HttpsError("invalid-argument", "replay");
  const ref = db().doc(`rankedMatches/${matchId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "match");
  const m = snap.data()!;
  if (!(m.players as string[]).includes(uid)) throw new HttpsError("permission-denied", "not-player");
  // 結果は 1 人 1 回だけ。2 回目からは、いまの状況を返すだけ(悪い結果を、入り直して出し直すことはできない)
  if (m.status !== "playing" || (m.results as Record<string, unknown> | undefined)?.[uid]) return resultFor(uid, m);
  if (now > (m.startAt as number) + SUBMIT_DEADLINE_MS) throw new HttpsError("deadline-exceeded", "late");
  // 続けて出すのを防ぐ(記録の計算し直しは重い)
  const metaRef = db().doc(`rankedMeta/${uid}`);
  await db().runTransaction(async (tx) => {
    const last = ((await tx.get(metaRef)).get("lastSubmitAt") as number | undefined) ?? 0;
    if (now - last < SUBMIT_INTERVAL_MS && now >= last) throw new HttpsError("resource-exhausted", "too-fast");
    tx.set(metaRef, { lastSubmitAt: now }, { merge: true });
  });
  const d = decodeReplay(replay, MAX_STEPS);
  if (!d) throw new HttpsError("invalid-argument", "replay-broken");
  const sc = rankedScore(m.seed as number, d.moves, d.steps);
  // 実際に遊んだ時間より早くは送れない(少しの余裕を見る)
  if (now < (m.startAt as number) + (sc.ticks / 120) * 1000 - 5000) throw new HttpsError("failed-precondition", "too-early");

  const final = await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data()!;
    if (cur.status !== "playing" || (cur.results as Record<string, unknown> | undefined)?.[uid]) return cur;
    const results = { ...(cur.results as Record<string, RankedScore>), [uid]: sc };
    if (cur.kind === "live" && Object.keys(results).length < 2) {
      tx.update(ref, { [`results.${uid}`]: sc });
      return { ...cur, results };
    }
    return finalize(tx, ref, { ...cur, results }, now);
  });
  // 相手を待つことになったら、相手の位置をいま見ておく(あとで rankedClaimWin を押したとき、更新が止まっているか分かるように)
  if (m.kind === "live" && final.status === "playing") {
    const opp = (m.players as string[]).find((u) => u !== uid);
    if (opp) await observeOpponent(matchId, opp, now).catch(() => undefined);
  }
  if (sc.ticks >= 600) {
    const prof = await profileOf(uid);
    const me = await playerOf(uid);
    // 1 人 1 つの種につき 1 本だけ残す(新しいもので上書き)。古いものは rankedSweep が消す
    await db().doc(`rankedRuns/${uid}_${m.seed as number}`).set({ seed: m.seed, uid, name: prof.name, rating: me.rating, replay, ticks: sc.ticks, grazes: sc.grazes, createdAt: now });
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
  // 同じ二人の対戦は、1 日に最初の PAIR_RATED_PER_DAY 回だけレートを動かす(2 つのアカウントで勝ちを重ねるのを防ぐ)
  let rated = true;
  if (m.kind !== "bot" && players.length === 2) {
    const pairRef = db().doc(`rankedPairs/${pairKey(players[0]!, players[1]!, now)}`);
    const n = ((await tx.get(pairRef)).get("n") as number | undefined) ?? 0;
    rated = n < PAIR_RATED_PER_DAY;
    tx.set(pairRef, { n: n + 1, at: now });
  }
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
    const da = rated ? ratingDelta(states[0]!.rating, states[1]!.rating, ra, states[0]!.games, false) : 0;
    const db2 = rated ? ratingDelta(states[1]!.rating, states[0]!.rating, rb, states[1]!.games, false) : 0;
    changes[a] = { before: states[0]!.rating, after: states[0]!.rating + da, result: ra };
    changes[b] = { before: states[1]!.rating, after: states[1]!.rating + db2, result: rb };
  }
  players.forEach((u, i) => {
    const s = states[i]!, ch = changes[u]!;
    tx.set(refs[i]!, {
      rating: ch.after, games: s.games + 1, best: Math.max(s.best, ch.after),
      wins: s.wins + (ch.result === 1 ? 1 : 0), losses: s.losses + (ch.result === 0 ? 1 : 0), draws: s.draws + (ch.result === 0.5 ? 1 : 0),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  });
  const done = { status: "done", results, changes, finishedAt: now, ...(rated ? {} : { rated: false }) };
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
  // 待ち行列の古い行も消す
  await rtdb().ref("rq").transaction((cur: Record<string, QueueEntry> | null) => {
    if (!cur) return cur;
    const q = { ...cur };
    for (const [k, e] of Object.entries(q)) if (queueRowExpired(e, now)) delete q[k];
    return q;
  });
  // 古い人の記録(種は週ごとに変わる)と、前の日の対戦の数を消す
  const oldRuns = await db().collection("rankedRuns").where("createdAt", "<", now - RUN_KEEP_MS).limit(300).get();
  const oldPairs = await db().collection("rankedPairs").where("at", "<", now - 2 * 86_400_000).limit(300).get();
  if (!oldRuns.empty || !oldPairs.empty) {
    const batch = db().batch();
    for (const d of [...oldRuns.docs, ...oldPairs.docs]) batch.delete(d.ref);
    await batch.commit();
  }
  return { closed: old.size, roomsRemoved: Object.keys(del).length, runsRemoved: oldRuns.size };
}

// ---- 相手を待つのをやめる ----

/** 相手の位置の記録(t = 遊んだステップ数)。seen: サーバーが前に見た t と、その時刻(rm/{matchId}/seen/{uid}。サーバーだけ) */
type Pos = { t?: unknown } | null;
type Seen = { t: number; at: number } | null;

/**
 * 相手がいなくなったか。
 * - 一度も位置が届いていない: 始まってから GONE_GRACE_MS 過ぎたら、いない
 * - 位置の更新が止まった: サーバーが前に見た t から変わらないまま GONE_GRACE_MS 過ぎたら、いない
 * - 遊んだはずの時間より、t が GONE_LAG_MS 以上遅れている(落ちてから記録を出さないなど)。
 *   遅い端末は、ゲームの時計が実際の時間より遅れる(30 秒ほど遅れることもある)ので、遅れだけで決めるときは長めに待つ
 * 締め切りを過ぎたら、これとは関係なく決着する(rankedClaim)
 */
export function opponentGone(p: Pos, seen: Seen, startAt: number, now: number): boolean {
  const elapsed = now - startAt;
  if (!p || typeof p.t !== "number") return elapsed > GONE_GRACE_MS;
  if (seen && seen.t === p.t && now - seen.at >= GONE_GRACE_MS) return true;
  return elapsed - (p.t / 120) * 1000 > GONE_LAG_MS;
}

/** 相手の位置を読み、t が前に見たときから変わっていれば、見た時刻を記録し直す。返すのは、位置と「前に見た」記録 */
async function observeOpponent(matchId: string, opp: string, now: number): Promise<{ p: Pos; seen: Seen }> {
  const [ps, ss] = await Promise.all([rtdb().ref(`rm/${matchId}/p/${opp}`).get(), rtdb().ref(`rm/${matchId}/seen/${opp}`).get()]);
  const p = ps.val() as Pos;
  const raw = ss.val() as { t?: unknown; at?: unknown } | null;
  const seen: Seen = raw && typeof raw.t === "number" && typeof raw.at === "number" ? { t: raw.t, at: raw.at } : null;
  if (p && typeof p.t === "number" && seen?.t !== p.t) await rtdb().ref(`rm/${matchId}/seen/${opp}`).set({ t: p.t, at: now });
  return { p, seen };
}

/**
 * 人同士の対戦で、記録を出したあと相手を待っている人が呼ぶ(rankedClaimWin)。相手がいなくなっていれば、その場で決着する
 * (相手は来なかった扱い = 0 秒)。まだ遊んでいそうなら pending を返す
 */
export async function rankedClaim(uid: string, data: unknown, now = Date.now()) {
  const matchId = (data as { matchId?: unknown })?.matchId;
  if (typeof matchId !== "string" || matchId.length < 8 || matchId.length > 40) throw new HttpsError("invalid-argument", "matchId");
  const ref = db().doc(`rankedMatches/${matchId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "match");
  const m = snap.data()!;
  const players = m.players as string[];
  if (!players.includes(uid)) throw new HttpsError("permission-denied", "not-player");
  if (m.status !== "playing" || m.kind !== "live") return resultFor(uid, m);
  if (!(m.results as Record<string, unknown> | undefined)?.[uid]) throw new HttpsError("failed-precondition", "submit-first");
  const opp = players.find((u) => u !== uid)!;
  const startAt = m.startAt as number;
  let gone = now > startAt + SUBMIT_DEADLINE_MS;
  if (!gone) { const o = await observeOpponent(matchId, opp, now); gone = opponentGone(o.p, o.seen, startAt, now); }
  if (!gone) return resultFor(uid, m);
  const final = await db().runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data()!;
    if (cur.status !== "playing") return cur;
    return finalize(tx, ref, cur, now);
  });
  return resultFor(uid, final);
}
