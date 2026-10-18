import { containsNgWord } from "./ngwords/index.js";

export const DURATIONS = { survive: [10, 20, 30, 45, 60, 90, 120], boss: [30, 60, 90, 120, 180] } as const;
export const PATTERNS = ["ring", "spiral", "aim", "rain", "sweep"] as const;
export type Pattern = (typeof PATTERNS)[number];
export type Mode = "survive" | "boss";

export interface Emitter {
  t: Pattern; x: number; y: number; s: number; e: number; i: number; c: number; v: number; r: number; k: number; ph: number;
}

export interface Stage {
  name: string;
  authorName: string;
  mode: Mode;
  durationSec: number;
  bossHp: number | null;
  bossMove: 0 | 1 | 2 | null;
  emitters: Emitter[];
  formatVersion: 1;
}

export const MAX_NAME = 20;
export const MAX_AUTHOR = 12;
export const MAX_EMITTERS = 8;
export const MAX_REPLAY_CHARS = 120_000;

export type Validated = { ok: true; stage: Stage; clearReplay: string } | { ok: false; error: string };

const r2 = (n: number) => Math.round(n * 100) / 100;
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const num = (v: unknown, lo: number, hi: number): number | null =>
  typeof v === "number" && Number.isFinite(v) && v >= lo && v <= hi ? v : null;
const int = (v: unknown, lo: number, hi: number): number | null => {
  const n = num(v, lo, hi);
  return n !== null && Number.isInteger(n) ? n : null;
};
const len = (s: string) => [...s].length;

/** クライアントから届いたデータを検証する。範囲外は丸めずに拒否し、通ったものは小数2桁に揃える */
export function validatePublish(input: unknown): Validated {
  if (!isObj(input)) return { ok: false, error: "invalid-data" };

  const name = typeof input.name === "string" ? input.name.trim() : "";
  if (len(name) < 1 || len(name) > MAX_NAME) return { ok: false, error: "name-length" };
  if (containsNgWord(name)) return { ok: false, error: "name-ng-word" };

  const authorName = typeof input.authorName === "string" ? input.authorName.trim() : "";
  if (len(authorName) < 1 || len(authorName) > MAX_AUTHOR) return { ok: false, error: "author-length" };
  if (containsNgWord(authorName)) return { ok: false, error: "author-ng-word" };

  if (input.mode !== "survive" && input.mode !== "boss") return { ok: false, error: "mode" };
  const mode: Mode = input.mode;
  const durationSec = int(input.durationSec, 1, 600);
  if (durationSec === null || !(DURATIONS[mode] as readonly number[]).includes(durationSec)) return { ok: false, error: "duration" };

  let bossHp: number | null = null;
  let bossMove: 0 | 1 | 2 | null = null;
  if (mode === "boss") {
    bossHp = int(input.bossHp, 100, 1000);
    if (bossHp === null || bossHp % 50 !== 0) return { ok: false, error: "boss-hp" };
    const mv = int(input.bossMove, 0, 2);
    if (mv === null) return { ok: false, error: "boss-move" };
    bossMove = mv as 0 | 1 | 2;
  }

  if (!Array.isArray(input.emitters) || input.emitters.length < 1 || input.emitters.length > MAX_EMITTERS) {
    return { ok: false, error: "emitter-count" };
  }
  const emitters: Emitter[] = [];
  for (const raw of input.emitters) {
    if (!isObj(raw) || !(PATTERNS as readonly unknown[]).includes(raw.t)) return { ok: false, error: "emitter-pattern" };
    const x = num(raw.x, 0, 1), y = num(raw.y, 0, 0.6), s = num(raw.s, 0, 180), e = num(raw.e, 0, 180);
    const i = num(raw.i, 0.05, 2), c = int(raw.c, 1, 36), v = num(raw.v, 1, 5), r = num(raw.r, -90, 90);
    const k = int(raw.k, 0, 4), ph = int(raw.ph ?? 0, 0, 3);
    if ([x, y, s, e, i, c, v, r, k, ph].some((n) => n === null)) return { ok: false, error: "emitter-range" };
    if (mode === "survive" && (s! >= durationSec || e! <= s!)) return { ok: false, error: "emitter-timing" };
    emitters.push({ t: raw.t as Pattern, x: r2(x!), y: r2(y!), s: r2(s!), e: r2(e!), i: r2(i!), c: c!, v: r2(v!), r: Math.round(r!), k: k!, ph: ph! });
  }

  const replay = input.clearReplay;
  if (typeof replay !== "string" || replay.length < 8 || replay.length > MAX_REPLAY_CHARS || !/^[A-Za-z0-9+/]+={0,2}$/.test(replay)) {
    return { ok: false, error: "replay" };
  }

  return {
    ok: true,
    clearReplay: replay,
    stage: { name, authorName, mode, durationSec, bossHp, bossMove, emitters, formatVersion: 1 },
  };
}

export const REPORT_REASONS = ["inappropriate_name", "impossible", "other"] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];
