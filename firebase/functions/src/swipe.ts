import { createSim, mulberry, type SimStage } from "./fullsim.js";

/**
 * スワイプ弾幕のサーバー側の計算(アプリの DanmakuCore の SwipeScoring / SwipeClip / SwipeClipPicker / SwipeFeed / SwipeRun の移植)。
 * 点数は BigInt。アプリと 1 桁も違わないことは、test/swipe.test.ts が Swift 版の正解データで確かめている。
 */

// ---------- 点数 ----------
export const GRAZE_BASE = 100n, CLEAR_BASE = 50_000n;
export const COMBO_LAPSE_STEPS = 180, BOMB_GAUGE = 40, COMBO_PER_DOUBLING = 8;

const pow = (b: bigint, e: number): bigint => b ** BigInt(Math.max(0, e));

export class SwipeScoring {
  score = 0n;
  streak = 0;
  combo = 0;
  gauge = 0;
  bombPending = false;
  private lastGrazeStep = 0;
  private streakFactor = 1n;

  static grazePoints(combo: number, streakFactor: bigint): bigint {
    const c = Math.max(0, combo);
    const doubled = pow(2n, Math.trunc(c / COMBO_PER_DOUBLING)) * (GRAZE_BASE * BigInt(COMBO_PER_DOUBLING + (c % COMBO_PER_DOUBLING)));
    return (doubled / BigInt(COMBO_PER_DOUBLING)) * streakFactor;
  }
  get currentGrazePoints(): bigint { return SwipeScoring.grazePoints(this.combo, this.streakFactor); }

  beginClip() { this.combo = 0; this.lastGrazeStep = 0; this.bombPending = false; }

  graze(step: number) {
    if (this.combo > 0 && step - this.lastGrazeStep < COMBO_LAPSE_STEPS) this.combo += 1; else this.combo = 1;
    this.lastGrazeStep = step;
    this.score += this.currentGrazePoints;
    this.gauge += 1;
    if (this.gauge >= BOMB_GAUGE) { this.gauge = 0; this.bombPending = true; }
  }

  /** 1 ステップの最後。ボムが出たら true(粒の点は加算済み) */
  endStep(step: number, bulletCount: number, hit = false): boolean {
    if (this.combo > 0 && step - this.lastGrazeStep >= COMBO_LAPSE_STEPS) this.combo = 0;
    const pending = this.bombPending;
    this.bombPending = false;
    if (!pending || hit) return false;
    this.collectCoins(bulletCount);
    return true;
  }

  clear(bulletCount: number) {
    const doublings = pow(2n, Math.trunc(this.combo / COMBO_PER_DOUBLING)) * CLEAR_BASE;
    this.score += doublings * (this.streakFactor * 3n);
    this.streak += 1;
    this.streakFactor *= 3n;
    this.collectCoins(bulletCount);
  }

  hit() { this.streak = 0; this.streakFactor = 1n; this.combo = 0; this.bombPending = false; }
  skip() { this.streak = 0; this.streakFactor = 1n; }

  private collectCoins(bulletCount: number) {
    this.score += (this.currentGrazePoints / 2n) * BigInt(Math.max(0, bulletCount));
  }
}

/** ランキングの並べ替え用: 桁数(3 桁、0 埋め) + 数字 */
export const rankingKey = (n: bigint): string => { const d = n.toString(); return d.length.toString().padStart(3, "0") + d; };

// ---------- クリップ ----------
export const PLAY_STEPS = 1200, GO_STEPS = 60, START_SHIELD_STEPS = 84, READY_STEPS = 144;
const COLUMNS = 12, ROWS = 8, W = 360, H = 540;
export const startTick = (seconds: number) => READY_STEPS + Math.round(seconds / (1 / 120));

type BulletLike = { x: number; y: number; vx: number; vy: number; script: number; radius?: number };

function distanceSquared(b: BulletLike, x: number, y: number, isBeam: boolean, isBlast: boolean): number {
  if (isBeam) {
    const rx = x - b.x, ry = y - b.y;
    const along = rx * b.vx + ry * b.vy;
    return along < 0 ? rx * rx + ry * ry : rx * rx + ry * ry - along * along;
  }
  if (isBlast) {
    const dx = x - b.x, dy = y - b.y;
    const edge = Math.max(0, Math.sqrt(dx * dx + dy * dy) - (b.radius ?? 0));
    return edge * edge;
  }
  let m = Infinity;
  for (const k of [0, 0.3, 0.6]) {
    const dx = b.x + b.vx * k - x, dy = b.y + b.vy * k - y;
    const d = dx * dx + dy * dy;
    if (d < m) m = d;
  }
  return m;
}

import { BEAM_SCRIPT, BLAST_SCRIPT } from "./adpatterns.js";

export function safestPosition(bullets: readonly BulletLike[]): { x: number; y: number } {
  let best = -Infinity;
  let at = { x: W / 2, y: H * 0.85 };
  for (let gx = 0; gx < COLUMNS; gx++) {
    for (let gy = 0; gy < ROWS; gy++) {
      const x = 30 + (gx * 300) / 11;
      const y = H * 0.5 + (gy * H * 0.42) / 7;
      let m = 1e9;
      for (const b of bullets) {
        const d = distanceSquared(b, x, y, b.script === BEAM_SCRIPT, b.script === BLAST_SCRIPT);
        if (d < m) m = d;
      }
      // Swift の (…).rounded() は 0.5 を 0 から遠ざける向きに丸める
      const v = (Math.sqrt(m) - Math.abs(x - W / 2) * 0.03) * 100;
      const score = v < 0 ? -Math.round(-v) : Math.round(v);
      if (score > best) { best = score; at = { x, y }; }
    }
  }
  return at;
}

export function prepareClip(stage: SimStage, atSeconds: number) {
  const sim = createSim(stage, "standard", undefined, { swipe: true });
  sim.fastForward(startTick(atSeconds));
  const p = safestPosition(sim.bullets);
  sim.place(p.x, p.y);
  sim.giveShield(START_SHIELD_STEPS);
  return sim;
}

// ---------- 区間の選び方 ----------
export const SAMPLE_EVERY = 60, WINDOW = PLAY_STEPS / SAMPLE_EVERY, SKIP_LEADING = 4, MIN_AVERAGE = 15, MAX_CANDIDATES = 5, MIN_SPACING = 10;
export interface Candidate { at: number; total: number }
export const estimatedClearRate = (avg: number) => Math.min(0.95, Math.max(0.05, 1.1 - avg / 250));

export function sampleStage(stage: SimStage): { counts: number[]; gaps: boolean[] } {
  const sim = createSim(stage, "standard", undefined, { swipe: true });
  sim.setInvincible(true);
  sim.setCountsGrazes(false);
  const counts: number[] = [], gaps: boolean[] = [];
  const cap = sim.waveLimitTicks + 120 * 3600;
  while (sim.outcome === "playing" && sim.tick < cap) {
    if (sim.tick >= READY_STEPS && (sim.tick - READY_STEPS) % SAMPLE_EVERY === 0) {
      counts.push(sim.bullets.length);
      gaps.push(sim.isIntermission);
    }
    sim.step(0, 0);
  }
  return { counts, gaps };
}

export function pickCandidates(counts: number[], gaps: boolean[]): Candidate[] {
  const w = WINDOW;
  if (counts.length < w) return [];
  const last = counts.length - w;
  const first = last >= SKIP_LEADING ? SKIP_LEADING : 0;
  const sum = [0], gapSum = [0];
  for (let i = 0; i < counts.length; i++) { sum.push(sum[i]! + counts[i]!); gapSum.push(gapSum[i]! + (gaps[i] ? 1 : 0)); }
  let windows: { j: number; total: number }[] = [];
  for (let j = first; j <= last; j++) {
    const total = sum[j + w]! - sum[j]!;
    const gapCount = gapSum[Math.min(j + w + 1, counts.length)]! - gapSum[j]!;
    if (gapCount === 0 && total >= MIN_AVERAGE * w) windows.push({ j, total });
  }
  windows = windows.sort((a, b) => (a.total !== b.total ? b.total - a.total : a.j - b.j));
  const picked: { j: number; total: number }[] = [];
  for (const c of windows) {
    if (picked.length === MAX_CANDIDATES) break;
    if (picked.every((p) => Math.abs(p.j - c.j) >= MIN_SPACING)) picked.push(c);
  }
  return picked.map((p) => ({ at: p.j * 0.5, total: p.total }));
}

export const candidatesOf = (stage: SimStage) => { const s = sampleStage(stage); return pickCandidates(s.counts, s.gaps); };

// ---------- 並び ----------
export interface FeedEntry { id: string; d: number; author: string }
const START_RATE = 850, STEP_RATE = 40, FLOOR_RATE = 80, NARROW = 100, WIDE = 200, MIN_POOL = 20;
export const targetRate = (streak: number) => Math.max(FLOOR_RATE, START_RATE - STEP_RATE * Math.max(0, streak));
const order = (a: FeedEntry, b: FeedEntry) => (a.d !== b.d ? a.d - b.d : a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

export function pickFeed(pool: FeedEntry[], seed: number, index: number, streak: number, used: Set<string>, excluded: Set<string>): FeedEntry | null {
  const target = targetRate(streak);
  const open = pool.filter((e) => !used.has(e.id) && !excluded.has(e.author));
  if (open.length === 0) return null;
  const inRange = (width: number) => open.filter((e) => Math.abs(e.d - target) <= width);
  let chosen = inRange(NARROW);
  if (chosen.length < MIN_POOL) chosen = inRange(WIDE);
  if (chosen.length < MIN_POOL) {
    chosen = [...open].sort((a, b) => { const x = Math.abs(a.d - target), y = Math.abs(b.d - target); return x !== y ? x - y : order(a, b); }).slice(0, MIN_POOL);
  }
  chosen.sort(order);
  const rng = mulberry((seed + Math.imul(index, 0x9e3779b9)) >>> 0);
  return chosen[Math.min(chosen.length - 1, Math.floor(rng() * chosen.length))]!;
}

// ---------- 1 プレイ ----------
export interface ClipInput { go: ArrayLike<number>; goCount: number; moves: ArrayLike<number>; moveCount: number; skipped: boolean }
export interface RunResult {
  score: bigint; streak: number; bestStreak: number; clipsPlayed: number; clipsCleared: number; clipIDs: string[];
  scoreAfterEachClip: string[]; bombs: number; grazes: number; endedByHit: boolean; abandoned: boolean; invalid: string | null;
}
export type ClipSource = (id: string) => { stage: SimStage; at: number } | null;
type ClipEnd = "cleared" | "hit" | "skipped" | "abandoned";

export function playRun(seed: number, pool: FeedEntry[], excluded: Set<string>, source: ClipSource, clips: ClipInput[]): RunResult {
  const r: RunResult = { score: 0n, streak: 0, bestStreak: 0, clipsPlayed: 0, clipsCleared: 0, clipIDs: [], scoreAfterEachClip: [], bombs: 0, grazes: 0, endedByHit: false, abandoned: false, invalid: null };
  const sc = new SwipeScoring();
  const used = new Set<string>();
  for (let index = 0; index < clips.length; index++) {
    const entry = pickFeed(pool, seed, index, sc.streak, used, excluded);
    if (!entry) { r.invalid = "pool-exhausted"; break; }
    const clip = source(entry.id);
    if (!clip) { r.invalid = `missing-stage:${entry.id}`; break; }
    used.add(entry.id);
    r.clipIDs.push(entry.id);
    r.clipsPlayed += 1;
    const end = playClip(clip.stage, clip.at, clips[index]!, sc, r);
    r.bestStreak = Math.max(r.bestStreak, sc.streak);
    r.scoreAfterEachClip.push(sc.score.toString());
    if (end === "cleared") r.clipsCleared += 1;
    else if (end === "hit") r.endedByHit = true;
    else if (end === "abandoned") r.abandoned = true;
    if (end === "hit" || end === "abandoned") break;
  }
  r.score = sc.score;
  r.streak = sc.streak;
  return r;
}

const coinBullets = (bullets: readonly BulletLike[]) => bullets.reduce((n, b) => n + (b.script === BEAM_SCRIPT || b.script === BLAST_SCRIPT ? 0 : 1), 0);

function playClip(stage: SimStage, at: number, input: ClipInput, sc: SwipeScoring, r: RunResult): ClipEnd {
  const sim = prepareClip(stage, at);
  sc.beginClip();
  for (let i = 0; i < Math.min(input.goCount, GO_STEPS); i++) sim.nudgePlayer(input.go[i * 2]!, input.go[i * 2 + 1]!);
  const count = Math.min(input.moveCount, PLAY_STEPS);
  for (let n = 1; n <= PLAY_STEPS; n++) {
    if (n > count) {
      if (input.skipped) { sc.skip(); return "skipped"; }
      return "abandoned";
    }
    sim.step(input.moves[(n - 1) * 2]!, input.moves[(n - 1) * 2 + 1]!);
    for (let g = 0; g < sim.grazedThisStep.length; g++) { sc.graze(n); r.grazes += 1; }
    const hit = sim.outcome === "hit";
    if (sc.endStep(n, coinBullets(sim.bullets), hit)) {
      sim.clearBullets();
      sim.giveShield(120);
      r.bombs += 1;
    }
    if (hit) { sc.hit(); return "hit"; }
    if (n === PLAY_STEPS || sim.outcome === "cleared") { sc.clear(coinBullets(sim.bullets)); return "cleared"; }
  }
  return "cleared";
}
