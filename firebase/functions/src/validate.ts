import { validatePath } from "./custompath.js";
import { containsNgWord } from "./ngwords/index.js";

/** ボスの動きの種類の数。0=止まる 1=横にゆっくり 2=横にはやい 3=上下 4=円 5=8の字 6=ワープ 7=円(逆) 8=8の字(逆) 9=横ゆっくり(逆) 10=横はやい(逆)(Swift の Simulation.bossMoveCount と同じ) */
export const BOSS_MOVE_COUNT = 11;

export const WAVE_DURATIONS = { survive: [10, 20, 30, 45, 60, 90, 120], boss: [30, 60, 90, 120, 180] } as const;
export const MAX_WAVES = 6;
export const INTERMISSION_BUDGET = 2;

export const DURATIONS = { survive: [10, 20, 30, 45, 60, 90, 120], boss: [0, 30, 60, 90, 120, 180], damage: [30, 60, 90, 120, 180], sequence: [] } as const;
// 並びを変えない(乱数シードに順番を使っている)。新しいものは必ず後ろに足す
export const PATTERNS = ["ring", "spiral", "aim", "rain", "sweep", "sideL", "sideR", "corner", "homing", "flower", "star", "heart", "beam", "cross", "accel", "bounce", "stopgo", "split", "timed", "twinRing", "tripleRing", "pinwheel", "ripple", "whirl", "slither", "curtain", "swayFan", "drizzle", "comet", "shotgun", "sniper", "twinAim", "zigzagAim", "accelRing", "homingRing", "bounceRing", "freezeRing", "shatterRing", "pulseRing", "freezeCurtain", "splitCurtain", "wavyRing", "petalFan", "waveSpiral", "tide", "ladder", "helix", "rapidFan", "lightRain", "custom", "chargeBeam", "boomerang", "giantOrb", "sweepLaser", "mine", "meteor", "gridLaser", "gravity", "orbit", "snake", "bubble", "swirl", "angelTwin", "angelFeather", "angelHalo", "angelCross", "angelParadise", "kitsuneLanterns", "kitsuneBarrier", "kitsuneSunshower", "kitsuneTorii", "kitsuneDance", "iceCage", "iceIcicles", "iceBlizzard", "iceFreeze", "iceMirror", "reaperScythe", "reaperSouls", "reaperChains", "reaperDeadline", "reaperRiver", "witchAbyss", "witchBubbles", "witchTentacles", "witchMaelstrom", "witchInk"] as const;
export type Pattern = (typeof PATTERNS)[number];
export type Mode = "survive" | "boss" | "damage" | "sequence";
export type WaveKind = "survive" | "boss";
/** 見た目のテーマ。classic は標準(データには入れない) */
export const THEMES = ["sakura", "ocean", "aurora", "gold", "neon", "rainbow"] as const;
export type Theme = (typeof THEMES)[number];
export type LifeMode = "lives" | "hp";
export const LIVES_RANGE = [1, 5] as const;
export const HP_RANGE = [3, 20] as const;

export interface Emitter {
  t: Pattern; x: number; y: number; s: number; e: number; i: number; c: number; v: number; r: number; k: number; ph: number;
  /** 出す場所(ボス戦・ダメージ勝負): 0 または未指定 = ボスの位置、1 = x, y の場所 */
  p?: 0 | 1;
  /** パターン全体を回す角度(度、-180〜180)。0 または未指定 = 回さない */
  a?: number;
  /** 弾幕作成モードで描いた軌道(t が custom のときだけ) */
  path?: number[];
  /** 弾の見た目(1=くの字 2=丸。未指定=パターンの標準)。見た目だけ */
  sh?: 1 | 2;
  /** 左右反転(線対称)。1 のときだけ入れる */
  mir?: 1;
}

export interface Wave {
  kind: WaveKind;
  durationSec: number;
  bossHp: number | null;
  bossMove: number | null;
  emitters: Emitter[];
  warning?: true;
  defeat?: number;
  /** ボスの大きさ(0=小 2=大。中=標準は入れない)。当たる範囲も変わる */
  bossSize?: number;
  /** 雑魚の姿の大きさ(0〜2)。見た目だけ */
  mooks?: number;
  /** ボスの見た目(1〜5。標準=0は入れない。5 は堕天使で、位置と当たる範囲が変わる)・雑魚の見た目(1〜4)。図形のボスと雑魚は見た目だけ */
  bossLook?: number;
  mookLook?: number;
  /** 覚醒する段階(2 か 3)。ボスの場面だけ */
  awaken?: number;
  /** ボスの位置(動きの中心。x は 0.2〜0.8、y は 0.1〜0.3、0.05 刻み。標準=x 0.5, y 0.2 は入れない) */
  bossX?: number;
  bossY?: number;
}

export interface Stage {
  /** ボスの位置(動きの中心)。標準は入れない */
  bossX?: number;
  bossY?: number;
  name: string;
  authorName: string;
  mode: Mode;
  durationSec: number;
  bossHp: number | null;
  bossMove: number | null;
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
  bossSize?: number;
  mooks?: number;
  bossLook?: number;
  mookLook?: number;
  /** 覚醒する段階(2 か 3)。ボス戦・ダメージ勝負だけ */
  awaken?: number;
  /** 自機の撃ち方(標準=standard は入れない)。作者が決めて、遊ぶ全員がその撃ち方で遊ぶ */
  shot?: "spread" | "heavy";
  /** 作者が付けた、毎日のごほうびの演出(報酬の番号。種類ごとに1つまで、種類の順)。見た目だけ */
  rewardFx?: number[];
  /** 世界のステージ一覧のプレビューを始める秒(1〜長さの30%まで。0 は入れない)。見た目だけ */
  previewStart?: number;
  /** 一覧でプレビューを見せない(ネタバレ防止)。見た目だけ */
  noPreview?: true;
}

/** 毎日のごほうび: 全部で365個、5種類(軌跡・火花・オーラ・爆発・称号)。ステージに付けられるのは称号を除く4種類 */
const REWARD_TOTAL = 365;
const REWARD_KIND_COUNT = 5;
const REWARD_FX_KINDS = 4;

/** 大きさ・見た目の共通の検査: 範囲外は不正。標準の値は保存しない(undefined を返す) */
function optInt(v: unknown, lo: number, hi: number, std: number | null): { ok: true; v: number | undefined } | { ok: false } {
  if (v === undefined || v === null) return { ok: true, v: undefined };
  const n = int(v, lo, hi);
  if (n === null) return { ok: false };
  return { ok: true, v: n === std ? undefined : n };
}

/** ボスの位置の指定(0.05 刻み)。範囲外・刻み違いは null。標準の位置と同じなら undefined(入れない) */
function homeVal(v: unknown, lo: number, hi: number, std: number): { ok: boolean; v?: number } {
  if (v === undefined || v === null) return { ok: true };
  if (typeof v !== "number" || !Number.isFinite(v) || v < lo - 1e-9 || v > hi + 1e-9) return { ok: false };
  const r = Math.round(v * 20) / 20;
  if (Math.abs(r - v) > 1e-6) return { ok: false };
  return Math.abs(r - std) < 1e-6 ? { ok: true } : { ok: true, v: r };
}

/** ボスの見た目の最大の番号(0〜4 は図形、5 は堕天使、6 は九尾の巫女、7 は雪の女王)。アプリの BossCharacter.maxLook と同じ */
export const BOSS_LOOK_MAX = 9;
/** 専用の絵を持つボスの番号の最小値(これ以上は、大きさ・動きの設定を使わない) */
export const BOSS_CHARACTER_MIN = 5;
/** 堕天使だけが使える技。堕天使(bossLook 5)のボスの場面にだけ置ける */
export const FALLEN_ANGEL_PATTERNS = ["angelTwin", "angelFeather", "angelHalo", "angelCross", "angelParadise"] as const;
/** 九尾の巫女だけが使える技。九尾(bossLook 6)のボスの場面にだけ置ける */
export const KITSUNE_PATTERNS = ["kitsuneLanterns", "kitsuneBarrier", "kitsuneSunshower", "kitsuneTorii", "kitsuneDance"] as const;
/** 雪の女王だけが使える技。雪の女王(bossLook 7)のボスの場面にだけ置ける */
export const ICE_QUEEN_PATTERNS = ["iceCage", "iceIcicles", "iceBlizzard", "iceFreeze", "iceMirror"] as const;
/** 死神だけが使える技。死神(bossLook 8)のボスの場面にだけ置ける */
export const REAPER_PATTERNS = ["reaperScythe", "reaperSouls", "reaperChains", "reaperDeadline", "reaperRiver"] as const;
/** 深海の魔女だけが使える技。魔女(bossLook 9)のボスの場面にだけ置ける */
export const WITCH_PATTERNS = ["witchAbyss", "witchBubbles", "witchTentacles", "witchMaelstrom", "witchInk"] as const;
/** ボスのキャラクター専用の技と、持ち主の見た目の番号(堕天使 5、九尾 6、雪の女王 7、死神 8、魔女 9)。アプリの Pattern.moves(of:) と同じ */
const MOVE_OWNERS: ReadonlyArray<readonly [readonly string[], number]> = [[FALLEN_ANGEL_PATTERNS, 5], [KITSUNE_PATTERNS, 6], [ICE_QUEEN_PATTERNS, 7], [REAPER_PATTERNS, 8], [WITCH_PATTERNS, 9]];
/** ボスのキャラクター専用の技を、持ち主でない見た目のボスに置いていないか(true なら不正) */
const wrongBossPattern = (list: Emitter[], look: number | undefined): boolean =>
  list.some((m) => MOVE_OWNERS.some(([moves, owner]) => moves.includes(m.t) && look !== owner));

/** 時間無制限のボス戦を打ち切る長さ(秒)。アプリの Stage.unlimitedCapSec と同じ */
export const UNLIMITED_CAP_SEC = 600;
/** 実際に使う制限時間(秒) */
export const timeLimitSec = (mode: string, durationSec: number) => (mode === "boss" && durationSec === 0 ? UNLIMITED_CAP_SEC : durationSec);   // 連戦の durationSec は、場面の合計(切り替えの時間を含む)

export const BGM_COUNT = 5;

export const MAX_NAME = 20;
export const MAX_AUTHOR = 12;
export const MAX_EMITTERS = 8;
export const MAX_REPLAY_CHARS = 120_000;

export type Validated = { ok: true; stage: Stage; clearReplay: string | null } | { ok: false; error: string };

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
    const i = num(item.i, 0.05, 15), c = int(item.c, 1, 36), v = num(item.v, 1, 5), r = num(item.r, -90, 90);
    const k = int(item.k, 0, 4), ph = int(item.ph ?? 0, 0, 3);
    const fp = int(item.p ?? 0, 0, 1);
    const ang = int(item.a ?? 0, -180, 180);
    const sh = int(item.sh ?? 0, 0, 2);   // 0 は標準
    const mir = int(item.mir ?? 0, 0, 1);
    if ([x, y, s, e, i, c, v, r, k, ph, fp, ang, sh, mir].some((n) => n === null)) return { ok: false, error: "emitter-range" };
    // 回せないパターン(雨・横切り・隅・掃射)に角度は付けられない
    if (ang !== 0 && ["rain", "sweep", "sideL", "sideR", "corner"].includes(item.t as string)) return { ok: false, error: "emitter-range" };
    // 描いた軌道は、custom のときだけ付き、custom には必ず付く
    const isCustom = item.t === "custom";
    const path = isCustom ? validatePath(item.path) : null;
    if (isCustom ? path === null : item.path !== undefined && item.path !== null) return { ok: false, error: "emitter-path" };
    if (opts.survive && fp === 1) return { ok: false, error: "emitter-point" };
    if (opts.survive && ph !== 0) return { ok: false, error: "emitter-range" };
    if (opts.survive && (s! >= opts.limit || e! <= s!)) return { ok: false, error: "emitter-timing" };
    list.push({ t: item.t as Pattern, x: r2(x!), y: r2(y!), s: r2(s!), e: r2(e!), i: r2(i!), c: c!, v: r2(v!), r: Math.round(r!), k: k!, ph: ph!, ...(fp === 1 ? { p: 1 as const } : {}), ...(ang !== 0 ? { a: ang! } : {}), ...(path ? { path } : {}), ...(sh ? { sh: sh as 1 | 2 } : {}), ...(mir === 1 ? { mir: 1 as const } : {}) });
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
    let bossHp: number | null = null, bossMove: number | null = null;
    if (kind === "boss") {
      bossHp = int(w.bossHp, 100, 1000);
      if (bossHp === null || bossHp % 50 !== 0) return { ok: false, error: "wave-boss-hp" };
      const mv = int(w.bossMove, 0, BOSS_MOVE_COUNT - 1);
      if (mv === null) return { ok: false, error: "wave-boss-move" };
      bossMove = mv;
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
    const wSize = optInt(w.bossSize, 0, 2, 1);
    const wMooks = optInt(w.mooks, 0, 2, null);
    const wBossLook = optInt(w.bossLook, 0, BOSS_LOOK_MAX, 0);
    const wMookLook = optInt(w.mookLook, 0, 4, 0);
    const wAwaken = optInt(w.awaken, 2, 3, null);
    const wHx = homeVal(w.bossX, 0.2, 0.8, 0.5), wHy = homeVal(w.bossY, 0.1, 0.3, 0.2);
    if (!wHx.ok || !wHy.ok || ((wHx.v !== undefined || wHy.v !== undefined) && (kind !== "boss" || ((wBossLook as { v?: number }).v ?? 0) >= BOSS_CHARACTER_MIN))) return { ok: false, error: "wave-look" };
    if (!wSize.ok || !wMooks.ok || !wBossLook.ok || !wMookLook.ok || !wAwaken.ok) return { ok: false, error: "wave-look" };
    if (wAwaken.v !== undefined && kind !== "boss") return { ok: false, error: "wave-look" };
    // 専用の絵を持つボスは、大きさ・動きを使わない(アプリが保存しない値)
    if ((wBossLook.v ?? 0) >= BOSS_CHARACTER_MIN && (wSize.v !== undefined || bossMove !== 0)) return { ok: false, error: "wave-look" };
    if ((wSize.v !== undefined || wBossLook.v !== undefined) && kind !== "boss") return { ok: false, error: "wave-look" };
    // 堕天使・九尾の技は、そのボスの場面にだけ置ける
    if (wrongBossPattern(em.list, kind === "boss" ? wBossLook.v : undefined)) return { ok: false, error: "emitter-pattern" };
    if (wMookLook.v !== undefined && wMooks.v === undefined && w.mooks === undefined) return { ok: false, error: "wave-look" };
    total += d;
    list.push({ kind, durationSec: d, bossHp, bossMove, emitters: em.list, ...(warning ? { warning } : {}), ...(defeat !== undefined ? { defeat } : {}),
      ...(wSize.v !== undefined ? { bossSize: wSize.v } : {}), ...(wMooks.v !== undefined ? { mooks: wMooks.v } : {}),
      ...(wBossLook.v !== undefined ? { bossLook: wBossLook.v } : {}), ...(wMookLook.v !== undefined ? { mookLook: wMookLook.v } : {}),
      ...(wAwaken.v !== undefined ? { awaken: wAwaken.v } : {}),
      ...(wHx.v !== undefined ? { bossX: wHx.v } : {}), ...(wHy.v !== undefined ? { bossY: wHy.v } : {}) });
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
  let bossMove: number | null = null;
  if (mode === "boss") {
    bossHp = int(input.bossHp, 100, 1000);
    if (bossHp === null || bossHp % 50 !== 0) return { ok: false, error: "boss-hp" };
  }
  if (mode === "boss" || mode === "damage") {
    const mv = int(input.bossMove, 0, BOSS_MOVE_COUNT - 1);
    if (mv === null) return { ok: false, error: "boss-move" };
    bossMove = mv;
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

  const bSize = optInt(input.bossSize, 0, 2, 1);
  const bMooks = optInt(input.mooks, 0, 2, null);
  const bBossLook = optInt(input.bossLook, 0, BOSS_LOOK_MAX, 0);
  const bMookLook = optInt(input.mookLook, 0, 4, 0);
  const bAwaken = optInt(input.awaken, 2, 3, null);
  const bHx = homeVal(input.bossX, 0.2, 0.8, 0.5), bHy = homeVal(input.bossY, 0.1, 0.3, 0.2);
  if (!bHx.ok || !bHy.ok || ((bHx.v !== undefined || bHy.v !== undefined) && ((mode !== "boss" && mode !== "damage") || ((bBossLook as { v?: number }).v ?? 0) >= BOSS_CHARACTER_MIN))) return { ok: false, error: "look" };
  if (!bSize.ok || !bMooks.ok || !bBossLook.ok || !bMookLook.ok || !bAwaken.ok) return { ok: false, error: "look" };
  if (bAwaken.v !== undefined && mode !== "boss" && mode !== "damage") return { ok: false, error: "look" };
  // 専用の絵を持つボスは、大きさ・動きを使わない(アプリが保存しない値)
  if ((bBossLook.v ?? 0) >= BOSS_CHARACTER_MIN && (bSize.v !== undefined || bossMove !== 0)) return { ok: false, error: "look" };
  if ((bSize.v !== undefined || bBossLook.v !== undefined) && mode !== "boss" && mode !== "damage") return { ok: false, error: "look" };
  // 堕天使・九尾の技は、そのボスにだけ置ける
  if (wrongBossPattern(emitters, mode === "boss" || mode === "damage" ? bBossLook.v : undefined)) return { ok: false, error: "emitter-pattern" };
  if (mode === "sequence" && (bMooks.v !== undefined || bMookLook.v !== undefined)) return { ok: false, error: "look" };
  if (bMookLook.v !== undefined && input.mooks === undefined) return { ok: false, error: "look" };

  let shot: "spread" | "heavy" | undefined;
  if (input.shot !== undefined && input.shot !== null && input.shot !== "standard") {
    if (input.shot !== "spread" && input.shot !== "heavy") return { ok: false, error: "shot" };
    shot = input.shot;
  }

  // 毎日のごほうびの演出(0〜364。5個ごとに 軌跡・火花・オーラ・爆発・称号 と種類が回る。称号と同じ種類の重複は不正)
  let rewardFx: number[] | undefined;
  if (input.rewardFx !== undefined && input.rewardFx !== null) {
    if (!Array.isArray(input.rewardFx) || input.rewardFx.length > REWARD_FX_KINDS) return { ok: false, error: "reward-fx" };
    const byKind = new Map<number, number>();
    for (const raw of input.rewardFx) {
      const r = int(raw, 0, REWARD_TOTAL - 1);
      if (r === null || r % REWARD_KIND_COUNT >= REWARD_FX_KINDS || byKind.has(r % REWARD_KIND_COUNT)) return { ok: false, error: "reward-fx" };
      byKind.set(r % REWARD_KIND_COUNT, r);
    }
    if (byKind.size > 0) rewardFx = [...byKind.entries()].sort((a, b) => a[0] - b[0]).map((e) => e[1]);
  }

  // 一覧のプレビュー(見た目だけ)。開始秒は長さの30%まで(切り捨て)。「見せない」と開始秒は、同時に指定できない
  let previewStart: number | undefined;
  let noPreview: true | undefined;
  if (input.noPreview !== undefined && input.noPreview !== null && input.noPreview !== false) {
    if (input.noPreview !== true) return { ok: false, error: "preview" };
    noPreview = true;
  }
  if (input.previewStart !== undefined && input.previewStart !== null) {
    const maxStart = Math.floor(durationSec! * 0.3);
    const ps = int(input.previewStart, 0, maxStart);
    if (ps === null || noPreview) return { ok: false, error: "preview" };
    if (ps > 0) previewStart = ps;
  }

  // 「URLを知っている人だけ」の投稿(unlisted)は、クリア記録がなくてもよい。一覧には載らない
  const replay = input.unlisted === true ? null : input.clearReplay;
  if (replay !== null && (typeof replay !== "string" || replay.length < 8 || replay.length > MAX_REPLAY_CHARS || !/^[A-Za-z0-9+/]+={0,2}$/.test(replay))) {
    return { ok: false, error: "replay" };
  }

  return {
    ok: true,
    clearReplay: replay,
    stage: { name, authorName, mode, durationSec, bossHp, bossMove, emitters, formatVersion: 1, ...(lifeMode ? { lifeMode, lifeCount } : {}), ...(bgm !== undefined ? { bgm } : {}), ...look, ...(hideMarkers ? { hideMarkers } : {}), ...(waves ? { waves } : {}), ...(bossWarning ? { bossWarning } : {}), ...(bossDefeat !== undefined ? { bossDefeat } : {}),
      ...(bSize.v !== undefined ? { bossSize: bSize.v } : {}), ...(bMooks.v !== undefined ? { mooks: bMooks.v } : {}),
      ...(bBossLook.v !== undefined ? { bossLook: bBossLook.v } : {}), ...(bMookLook.v !== undefined ? { mookLook: bMookLook.v } : {}),
      ...(bAwaken.v !== undefined ? { awaken: bAwaken.v } : {}),
      ...(bHx.v !== undefined ? { bossX: bHx.v } : {}), ...(bHy.v !== undefined ? { bossY: bHy.v } : {}),
      ...(shot ? { shot } : {}), ...(rewardFx ? { rewardFx } : {}),
      ...(previewStart !== undefined ? { previewStart } : {}), ...(noPreview ? { noPreview } : {}) },
  };
}

/**
 * ランキングとコメントに出す名前(投稿者名)の検査。未指定・空は「匿名で出す」ので undefined。
 * 長さ(1〜12文字)とNGワードを検査する。不正なら ok: false
 */
export function validateDisplayName(raw: unknown): { ok: true; name: string | undefined } | { ok: false } {
  if (raw === undefined || raw === null) return { ok: true, name: undefined };
  if (typeof raw !== "string") return { ok: false };
  const name = raw.replace(/\s+/g, " ").trim();
  if (name === "") return { ok: true, name: undefined };
  if (len(name) > MAX_AUTHOR || containsNgWord(name)) return { ok: false };
  return { ok: true, name };
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
