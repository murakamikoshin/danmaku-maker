import { containsNgWord } from "./ngwords/index.js";

export const WAVE_DURATIONS = { survive: [10, 20, 30, 45, 60, 90, 120], boss: [30, 60, 90, 120, 180] } as const;
export const MAX_WAVES = 6;
export const INTERMISSION_BUDGET = 2;

export const DURATIONS = { survive: [10, 20, 30, 45, 60, 90, 120], boss: [0, 30, 60, 90, 120, 180], damage: [30, 60, 90, 120, 180], sequence: [] } as const;
// 並びを変えない(乱数シードに順番を使っている)。新しいものは必ず後ろに足す
export const PATTERNS = ["ring", "spiral", "aim", "rain", "sweep", "sideL", "sideR", "corner", "homing", "flower", "star", "heart", "beam", "cross", "accel", "bounce", "stopgo", "split", "timed"] as const;
export type Pattern = (typeof PATTERNS)[number];
export type Mode = "survive" | "boss" | "damage" | "sequence";
export type WaveKind = "survive" | "boss";
/** 見た目のテーマ。classic は標準(データには入れない) */
export const THEMES = ["sakura", "ocean", "aurora"] as const;
export type Theme = (typeof THEMES)[number];
export type LifeMode = "lives" | "hp";
export const LIVES_RANGE = [1, 5] as const;
export const HP_RANGE = [3, 20] as const;

export interface Emitter {
  t: Pattern; x: number; y: number; s: number; e: number; i: number; c: number; v: number; r: number; k: number; ph: number;
  /** 出す場所(ボス戦・ダメージ勝負): 0 または未指定 = ボスの位置、1 = x, y の場所 */
  p?: 0 | 1;
}

export interface Wave {
  kind: WaveKind;
  durationSec: number;
  bossHp: number | null;
  bossMove: 0 | 1 | 2 | null;
  emitters: Emitter[];
  warning?: true;
  defeat?: number;
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
  /** 自機の耐久。標準(ライフ1)のときは入れない */
  lifeMode?: LifeMode;
  lifeCount?: number;
  /** 遊ぶときに流れる BGM の番号(0〜4)。標準の曲のときは入れない */
  bgm?: number;
  /** ステージの見た目(作者が決める)。標準(classic)のときは入れない */
  themeBullets?: Theme;
  themeBackground?: Theme;
  themeShip?: Theme;
  /** 発射位置の予告(点線のひし形)を出さない。出す(標準)のときは入れない。生き残りのステージだけ */
  hideMarkers?: true;
  /** 連戦の場面(mode が sequence のとき) */
  waves?: Wave[];
  /** ボス戦・ダメージ勝負の開始前の警告 */
  bossWarning?: true;
  /** ボス戦の撃破の演出(標準=爆発は入れない) */
  bossDefeat?: number;
}

/** 時間無制限のボス戦を打ち切る長さ(秒)。アプリの Stage.unlimitedCapSec と同じ */
export const UNLIMITED_CAP_SEC = 600;
/** 実際に使う制限時間(秒) */
export const timeLimitSec = (mode: string, durationSec: number) => (mode === "boss" && durationSec === 0 ? UNLIMITED_CAP_SEC : durationSec);   // 連戦の durationSec は、場面の合計(切り替えの時間を含む)

export const BGM_COUNT = 5;

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

/** 発射台の一覧を検証して、丸めて返す。timing: 生き残りの場面は、開始と終わりの時間の整合も見る。fireFromPoint: ボスの場面だけ、好きな場所から出せる */
function validateEmitters(raw: unknown, opts: { survive: boolean; limit: number; boss: boolean }): { ok: true; list: Emitter[] } | { ok: false; error: string } {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_EMITTERS) return { ok: false, error: "emitter-count" };
  const list: Emitter[] = [];
  for (const item of raw) {
    if (!isObj(item) || !(PATTERNS as readonly unknown[]).includes(item.t)) return { ok: false, error: "emitter-pattern" };
    const x = num(item.x, 0, 1), y = num(item.y, 0, 0.6), s = num(item.s, 0, 180), e = num(item.e, 0, 180);
    const i = num(item.i, 0.05, 2), c = int(item.c, 1, 36), v = num(item.v, 1, 5), r = num(item.r, -90, 90);
    const k = int(item.k, 0, 4), ph = int(item.ph ?? 0, 0, 3);
    const fp = int(item.p ?? 0, 0, 1);
    if ([x, y, s, e, i, c, v, r, k, ph, fp].some((n) => n === null)) return { ok: false, error: "emitter-range" };
    if (opts.survive && fp === 1) return { ok: false, error: "emitter-point" };
    if (opts.survive && ph !== 0) return { ok: false, error: "emitter-range" };
    if (opts.survive && (s! >= opts.limit || e! <= s!)) return { ok: false, error: "emitter-timing" };
    list.push({ t: item.t as Pattern, x: r2(x!), y: r2(y!), s: r2(s!), e: r2(e!), i: r2(i!), c: c!, v: r2(v!), r: Math.round(r!), k: k!, ph: ph!, ...(fp === 1 ? { p: 1 as const } : {}) });
  }
  return { ok: true, list };
}

/** 連戦の場面を検証する */
function validateWaves(raw: unknown): { ok: true; list: Wave[]; total: number } | { ok: false; error: string } {
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > MAX_WAVES) return { ok: false, error: "wave-count" };
  const list: Wave[] = [];
  let total = 0;
  for (const w of raw) {
    if (!isObj(w) || (w.kind !== "survive" && w.kind !== "boss")) return { ok: false, error: "wave-kind" };
    const kind: WaveKind = w.kind;
    const d = int(w.durationSec, 1, 600);
    if (d === null || !(WAVE_DURATIONS[kind] as readonly number[]).includes(d)) return { ok: false, error: "wave-duration" };
    let bossHp: number | null = null, bossMove: 0 | 1 | 2 | null = null;
    if (kind === "boss") {
      bossHp = int(w.bossHp, 100, 1000);
      if (bossHp === null || bossHp % 50 !== 0) return { ok: false, error: "wave-boss-hp" };
      const mv = int(w.bossMove, 0, 2);
      if (mv === null) return { ok: false, error: "wave-boss-move" };
      bossMove = mv as 0 | 1 | 2;
    } else if ((w.bossHp ?? null) !== null || (w.bossMove ?? null) !== null) {
      return { ok: false, error: "wave-boss-hp" };
    }
    const em = validateEmitters(w.emitters, { survive: kind === "survive", limit: d, boss: kind === "boss" });
    if (!em.ok) return em;
    let warning: true | undefined;
    if (w.warning !== undefined && w.warning !== null && w.warning !== false) {
      if (w.warning !== true || kind !== "boss") return { ok: false, error: "wave-warning" };
      warning = true;
    }
    let defeat: number | undefined;
    if (w.defeat !== undefined && w.defeat !== null) {
      const dv = int(w.defeat, 0, 4);
      if (dv === null || kind !== "boss") return { ok: false, error: "wave-defeat" };
      if (dv !== 1) defeat = dv;   // 1(爆発)は標準なので、保存しない
    }
    total += d;
    list.push({ kind, durationSec: d, bossHp, bossMove, emitters: em.list, ...(warning ? { warning } : {}), ...(defeat !== undefined ? { defeat } : {}) });
  }
  return { ok: true, list, total: total + INTERMISSION_BUDGET * (list.length - 1) };
}

/** クライアントから届いたデータを検証する。範囲外は丸めずに拒否し、通ったものは小数2桁に揃える */
export function validatePublish(input: unknown): Validated {
  if (!isObj(input)) return { ok: false, error: "invalid-data" };

  const name = typeof input.name === "string" ? input.name.trim() : "";
  if (len(name) < 1 || len(name) > MAX_NAME) return { ok: false, error: "name-length" };
  if (containsNgWord(name)) return { ok: false, error: "name-ng-word" };

  const authorName = typeof input.authorName === "string" ? input.authorName.trim() : "";
  if (len(authorName) < 1 || len(authorName) > MAX_AUTHOR) return { ok: false, error: "author-length" };
  if (containsNgWord(authorName)) return { ok: false, error: "author-ng-word" };

  if (input.mode !== "survive" && input.mode !== "boss" && input.mode !== "damage" && input.mode !== "sequence") return { ok: false, error: "mode" };
  const mode: Mode = input.mode;
  const durationSec = int(input.durationSec, 0, 1200);   // 0 はボス戦の「時間無制限」。連戦は、場面の合計
  let waves: Wave[] | undefined;
  if (mode === "sequence") {
    const w = validateWaves(input.waves);
    if (!w.ok) return w;
    waves = w.list;
    if (durationSec !== w.total) return { ok: false, error: "duration" };   // 場面の合計と一致していること
  } else if (input.waves !== undefined && input.waves !== null) {
    return { ok: false, error: "waves" };
  } else if (durationSec === null || !(DURATIONS[mode] as readonly number[]).includes(durationSec)) return { ok: false, error: "duration" };

  let bossHp: number | null = null;
  let bossMove: 0 | 1 | 2 | null = null;
  if (mode === "boss") {
    bossHp = int(input.bossHp, 100, 1000);
    if (bossHp === null || bossHp % 50 !== 0) return { ok: false, error: "boss-hp" };
  }
  if (mode === "boss" || mode === "damage") {
    const mv = int(input.bossMove, 0, 2);
    if (mv === null) return { ok: false, error: "boss-move" };
    bossMove = mv as 0 | 1 | 2;
  }

  // 自機の耐久(未指定はライフ1)。標準と同じ指定は入れない(アプリの丸め方と同じ)
  let lifeMode: LifeMode | undefined;
  let lifeCount: number | undefined;
  if (input.lifeMode !== undefined && input.lifeMode !== null) {
    if (input.lifeMode !== "lives" && input.lifeMode !== "hp") return { ok: false, error: "life-mode" };
    const [lo, hi] = input.lifeMode === "lives" ? LIVES_RANGE : HP_RANGE;
    const c = int(input.lifeCount ?? 1, lo, hi);
    if (c === null) return { ok: false, error: "life-count" };
    if (!(input.lifeMode === "lives" && c === 1)) { lifeMode = input.lifeMode; lifeCount = c; }
  } else if (input.lifeCount !== undefined && input.lifeCount !== null && input.lifeCount !== 1) {
    return { ok: false, error: "life-count" };
  }

  let emitters: Emitter[] = [];
  if (mode === "sequence") {
    if (Array.isArray(input.emitters) && input.emitters.length > 0) return { ok: false, error: "emitter-count" };
  } else {
    const em = validateEmitters(input.emitters, { survive: mode === "survive", limit: durationSec!, boss: mode !== "survive" });
    if (!em.ok) return em;
    emitters = em.list;
  }

  // BGM(未指定は、モードごとの標準: 生き残り=0、それ以外=1)。標準と同じ指定は入れない
  let bgm: number | undefined;
  if (input.bgm !== undefined && input.bgm !== null) {
    const b = int(input.bgm, 0, BGM_COUNT - 1);
    if (b === null) return { ok: false, error: "bgm" };
    if (b !== (mode === "survive" ? 0 : 1)) bgm = b;
  }

  // ステージの見た目(未指定・classic は標準)
  const look: { themeBullets?: Theme; themeBackground?: Theme; themeShip?: Theme } = {};
  for (const key of ["themeBullets", "themeBackground", "themeShip"] as const) {
    const v = input[key];
    if (v === undefined || v === null || v === "classic") continue;
    if (typeof v !== "string" || !(THEMES as readonly string[]).includes(v)) return { ok: false, error: "theme" };
    look[key] = v as Theme;
  }

  // 発射位置の予告を出さない設定(生き残りだけ)
  let hideMarkers: true | undefined;
  if (input.hideMarkers !== undefined && input.hideMarkers !== null && input.hideMarkers !== false) {
    if (input.hideMarkers !== true || (mode !== "survive" && mode !== "sequence")) return { ok: false, error: "markers" };
    hideMarkers = true;
  }

  // ボス戦・ダメージ勝負の警告と、ボス戦の撃破の演出(連戦は、場面ごと)
  let bossWarning: true | undefined;
  if (input.bossWarning !== undefined && input.bossWarning !== null && input.bossWarning !== false) {
    if (input.bossWarning !== true || (mode !== "boss" && mode !== "damage")) return { ok: false, error: "warning" };
    bossWarning = true;
  }
  let bossDefeat: number | undefined;
  if (input.bossDefeat !== undefined && input.bossDefeat !== null) {
    const dv = int(input.bossDefeat, 0, 4);
    if (dv === null || mode !== "boss") return { ok: false, error: "defeat" };
    if (dv !== 1) bossDefeat = dv;
  }

  const replay = input.clearReplay;
  if (typeof replay !== "string" || replay.length < 8 || replay.length > MAX_REPLAY_CHARS || !/^[A-Za-z0-9+/]+={0,2}$/.test(replay)) {
    return { ok: false, error: "replay" };
  }

  return {
    ok: true,
    clearReplay: replay,
    stage: { name, authorName, mode, durationSec, bossHp, bossMove, emitters, formatVersion: 1, ...(lifeMode ? { lifeMode, lifeCount } : {}), ...(bgm !== undefined ? { bgm } : {}), ...look, ...(hideMarkers ? { hideMarkers } : {}), ...(waves ? { waves } : {}), ...(bossWarning ? { bossWarning } : {}), ...(bossDefeat !== undefined ? { bossDefeat } : {}) },
  };
}

export const REPORT_REASONS = ["inappropriate_name", "impossible", "other"] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];


export const MAX_COMMENT = 80;
export type CommentCheck = { ok: true; text: string } | { ok: false; error: string };

/** コメントの検証。前後の空白を除き、1〜80文字、NGワードとURLは拒否する */
export function validateComment(raw: unknown): CommentCheck {
  const text = typeof raw === "string" ? raw.replace(/\s+/g, " ").trim() : "";
  if (len(text) < 1 || len(text) > MAX_COMMENT) return { ok: false, error: "comment-length" };
  if (/https?:|www\.|[a-z0-9-]+\.(com|net|org|jp|io|co|me|ly|gg|xyz)\b|\/\//i.test(text)) return { ok: false, error: "comment-link" };
  if (containsNgWord(text)) return { ok: false, error: "comment-ng-word" };
  return { ok: true, text };
}
