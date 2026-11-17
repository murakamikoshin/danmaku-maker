/**
 * 竜王(bossLook 13)の技。アプリの DanmakuCore/Dragon.swift と 1 ビットも違わないように、同じ順番で計算する。
 * 試射場(art/bosses/patterns/engine.js の R.dragon*)を、クロージャを持たない状態機械にしたもの。
 * 竜王の部分は偶数ステップ(60Hz)だけ進める。速さは px/フレーム(弾は ×60 で px/秒)。
 */
import type { BossBullet } from "./bossscripts.js";

const W = 360, H = 540;
export const DRAGON_LOOK = 13;
export const DRAGON_RADIUS = 56;
export const DRAGON_MOVES = ["dragonBreath", "dragonRaid", "dragonGale", "dragonInhale", "dragonGlide", "dragonRoar", "dragonQuake", "dragonTail", "dragonRampage", "dragonEnd"] as const;
export type DragonMoveName = (typeof DRAGON_MOVES)[number];
export const dragonMoveIndex = (t: string): number => (DRAGON_MOVES as readonly string[]).indexOf(t);

export const DRAGON_PLAIN = 30, DRAGON_SUN = 31, DRAGON_TORNADO = 32, DRAGON_EMBER = 33, DRAGON_BODY = 34, DRAGON_DROP = 35;
const WINDUP = 30, RECOVER = 15, REST = 50, INV = 40, TAIL_LEN = 380;
/** 吸い込みで、自機の弾の速さを口の向きへ寄せる割合(アプリの Bullet.absorbLerp) */
const ABSORB_LERP = 1 - Math.sqrt(0.92);

/** BulletLook.Kind の番号(アプリと同じ並び)。look = 16 + 番号 × 2 + (姿 > 0) */
const KIND = { flame: 22, slash: 23, gust: 24, sun: 25, rock: 26, spine: 27, tornado: 28, ember: 29, pshot: 30 } as const;
type Kind = keyof typeof KIND;

export const enum Shape { Rect, Circle, Safe, Ring, Beam }
export interface Safe { x: number; y: number; r: number; vx: number }
export interface Zone {
  id: number; shape: Shape; x: number; y: number; r: number; w: number; h: number;
  warn: number; dur: number; t: number; bind: number; kill: boolean; sweep: number;
  vr: number; th: number; gapA: number; gapW: number; a: number; track: number; len: number; safe: Safe[];
}
const zoneOf = (shape: Shape, o: Partial<Zone>): Zone => ({
  id: 0, shape, x: 0, y: 0, r: 0, w: 0, h: 0, warn: 0, dur: 0, t: 0, bind: 0, kill: false, sweep: 0,
  vr: 0, th: 0, gapA: 0, gapW: 0, a: 0, track: 0, len: 900, safe: [], ...o,
});

export const enum Stage { Idle, Windup, Attack, Recover, Rest }
export interface Glide { x0: number; y0: number; x1: number; y1: number; n: number; i: number }
export interface DragonState {
  stage: Stage; move: number; lv: number; frame: number; stageStart: number;
  boffX: number; boffY: number; pose: number; windX: number; windY: number; pull: number; pullForce: number;
  absorbing: boolean; eaten: number; bind: number; inv: number; zones: Zone[];
  pc: number; resumeAt: number; nextZoneID: number;
  c0: number; c1: number; c2: number; c3: number; d0: number; d1: number;
  cracks: { x: number; y: number }[][]; glide: Glide | null;
}
export const newDragon = (): DragonState => ({
  stage: Stage.Idle, move: -1, lv: 0, frame: 0, stageStart: 0, boffX: 0, boffY: 0, pose: 0, windX: 0, windY: 0, pull: 0, pullForce: 0,
  absorbing: false, eaten: 0, bind: 0, inv: 0, zones: [], pc: 0, resumeAt: 0, nextZoneID: 1,
  c0: 0, c1: 0, c2: 0, c3: 0, d0: 0, d1: 0, cracks: [], glide: null,
});
export const cloneDragon = (d: DragonState): DragonState => ({
  ...d, zones: d.zones.map((z) => ({ ...z, safe: z.safe.map((c) => ({ ...c })) })), cracks: d.cracks.map((p) => p.map((q) => ({ ...q }))),
  glide: d.glide ? { ...d.glide } : null,
});

/** 場面・段階が変わったとき(アプリの DragonState.abort と同じ) */
export function abortDragon(d: DragonState) {
  d.stage = Stage.Idle; d.stageStart = d.frame; d.pc = 0; d.glide = null;
  d.boffX = 0; d.boffY = 0; d.pose = 0; d.windX = 0; d.windY = 0; d.pull = 0; d.pullForce = 0;
  d.absorbing = false; d.bind = 0; d.zones = []; d.cracks = [];
}

/** シミュレーションとのつなぎ */
export interface DragonEnv {
  d: DragonState;
  rng: () => number;
  px: () => number;
  py: () => number;
  setPlayer: (x: number, y: number) => void;
  bullets: () => BossBullet[];
  setBullets: (b: BossBullet[]) => void;
  /** 本体のずれを足す前の、ボスの位置(作者の決めた位置・動き) */
  base: () => { x: number; y: number };
  scale: number;
  maxBullets: number;
}

const dv = <T>(lv: number, a: T, b: T, c: T, e: T): T => (lv === 0 ? a : lv === 1 ? b : lv === 2 ? c : e);
const clamp = (v: number, a: number, b: number) => Math.max(a, Math.min(b, v));
const angDiff = (a: number, b: number) => {
  let d = a - b;
  while (d > Math.PI) d -= 2 * Math.PI;
  while (d < -Math.PI) d += 2 * Math.PI;
  return Math.abs(d);
};

export function bossPos(e: DragonEnv) {
  const p = e.base();
  return e.d.boffX === 0 && e.d.boffY === 0 ? p : { x: p.x + e.d.boffX, y: p.y + e.d.boffY };
}
const point = (e: DragonEnv, dx: number, dy: number) => { const b = bossPos(e); return { x: b.x + dx * e.scale, y: b.y + dy * e.scale }; };
export const mouth = (e: DragonEnv) => point(e, 22, -28);
const hand = (e: DragonEnv, right: boolean) => (right ? point(e, 76, 16) : point(e, -80, 16));
const wing = (e: DragonEnv, right: boolean) => (right ? point(e, 172, 24) : point(e, -172, 24));
const aimFrom = (e: DragonEnv, o: { x: number; y: number }) => Math.atan2(e.py() - o.y, e.px() - o.x);

const blank = (x: number, y: number): BossBullet => ({ x, y, vx: 0, vy: 0, color: 0, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0 });

function fire(e: DragonEnv, kind: Kind, x: number, y: number, a: number, s: number, r: number, life = 0, script = DRAGON_PLAIN, gravity = 0, persistent = false) {
  const bs = e.bullets();
  if (bs.length >= e.maxBullets) return;
  const b = blank(x, y);
  b.vx = Math.cos(a) * s * 60; b.vy = Math.sin(a) * s * 60;
  b.look = 16 + KIND[kind] * 2 + (e.d.lv > 0 ? 1 : 0);
  b.script = script;
  b.radius = r;
  b.fuse = life > 0 ? life / 60 : 0;
  b.gravity = gravity * 3600;
  if (persistent) b.u3 = 1;
  bs.push(b);
}

function addZone(e: DragonEnv, z: Zone) {
  z.id = e.d.nextZoneID;
  e.d.nextZoneID += 1;
  e.d.zones.push(z);
}

function bodyHit(e: DragonEnv, frames: number, r: number) {
  const bs = e.bullets();
  if (bs.length >= e.maxBullets) return;
  const b0 = bossPos(e);
  const b = blank(b0.x, b0.y + 10 * e.scale);
  b.script = DRAGON_BODY;
  b.radius = r * e.scale;
  b.fuse = frames / 60;
  bs.push(b);
}

function glideTo(e: DragonEnv, x: number, y: number, n: number) {
  const base = e.base();
  e.d.glide = { x0: e.d.boffX, y0: e.d.boffY, x1: x - base.x, y1: y - base.y, n, i: 0 };
}
function glideOffset(e: DragonEnv, dx: number, dy: number, n: number) {
  e.d.glide = { x0: e.d.boffX, y0: e.d.boffY, x1: dx, y1: dy, n, i: 0 };
}

/** 技を始める(アプリの dragonStart) */
export function dragonStart(d: DragonState, move: number, lv: number) {
  d.move = move; d.lv = lv; d.pc = 0;
  d.stage = Stage.Windup; d.stageStart = d.frame;
}

/** 弾の専用の動き。扱わないなら null(アプリの advanceDragonScript) */
export function stepDragonBullet(b: BossBullet, dt: number): "alive" | "gone" | null {
  switch (b.script) {
    case DRAGON_PLAIN: case DRAGON_DROP: case DRAGON_EMBER: {
      b.age += dt;
      if ((b.fuse ?? 0) > 0 && b.age >= (b.fuse ?? 0)) return "gone";
      if (b.gravity) b.vy += b.gravity * dt;
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    case DRAGON_SUN: {
      b.age += dt;
      const fuse = b.fuse ?? 0;
      if (b.age >= fuse) return "gone";
      const s = b.age / fuse;
      const u0 = b.u0 ?? 0, u1 = b.u1 ?? 0, u2 = b.u2 ?? 0, u3 = b.u3 ?? 0;
      const nx = u0 + (u2 - u0) * s, ny = u1 + (u3 - u1) * s * s;
      b.vx = (nx - b.x) / dt; b.vy = (ny - b.y) / dt;
      b.x = nx; b.y = ny;
      return "alive";
    }
    case DRAGON_TORNADO: {
      b.age += dt;
      if (b.age >= (b.fuse ?? 0)) return "gone";
      const f = b.age * 60;
      b.x = (b.u0 ?? 0) + Math.sin(f * 0.03 + (b.u2 ?? 0)) * 60;
      b.y = (b.u1 ?? 0) + Math.sin(f * 0.05) * 16;
      return "alive";
    }
    case DRAGON_BODY:
      b.age += dt;
      return b.age >= (b.fuse ?? 0) ? "gone" : "alive";
    default:
      return null;
  }
}
export const isDragonPersistent = (b: BossBullet): boolean =>
  b.script === DRAGON_BODY || b.script === DRAGON_TORNADO || b.script === DRAGON_SUN || (b.script === DRAGON_PLAIN && b.u3 === 1);

/** 60Hz の 1 フレーム(アプリの dragonFrame) */
export function dragonFrame(e: DragonEnv) {
  const d = e.d;
  d.frame += 1;
  const f = d.frame;
  if (d.inv > 0) d.inv -= 1;
  if (d.bind > 0) d.bind -= 1;
  switch (d.stage) {
    case Stage.Idle: break;
    case Stage.Windup:
      if (d.frame - d.stageStart >= WINDUP) { d.stage = Stage.Attack; d.stageStart = d.frame; d.pc = 0; d.resumeAt = f; }
      break;
    case Stage.Attack: {
      if (d.glide) {
        const g = { ...d.glide };
        g.i += 1;
        const t = g.i / g.n, ee = t * t * (3 - 2 * t);
        d.boffX = g.x0 + (g.x1 - g.x0) * ee; d.boffY = g.y0 + (g.y1 - g.y0) * ee;
        d.glide = g.i >= g.n ? null : g;
        if (d.glide !== null) break;
        d.resumeAt = f + 1;
        break;
      }
      if (f >= d.resumeAt && d.move >= 0) {
        if (!runMove(e, d.move)) {
          d.boffX = 0; d.boffY = 0; d.windX = 0; d.windY = 0; d.pull = 0; d.pullForce = 0;
          d.pose = 0; d.absorbing = false;
          d.stage = Stage.Recover; d.stageStart = d.frame;
        }
      }
      break;
    }
    case Stage.Recover:
      if (d.frame - d.stageStart >= RECOVER) { d.stage = Stage.Rest; d.stageStart = d.frame; }
      break;
    case Stage.Rest:
      if (d.frame - d.stageStart >= REST) { d.stage = Stage.Idle; d.stageStart = d.frame; }
      break;
  }
  // 火の粉は口へ吸い込まれる
  const bs = e.bullets();
  if (bs.some((b) => b.script === DRAGON_EMBER)) {
    const m = mouth(e);
    let w = 0;
    for (let i = 0; i < bs.length; i++) {
      const b = bs[i]!;
      if (b.script === DRAGON_EMBER) {
        const dx = m.x - b.x, dy = m.y - b.y;
        if (dx * dx + dy * dy < 14 * 14) continue;
        const a = Math.atan2(dy, dx), sp = Math.min(5, 1.2 + b.age * 60 * 0.05) * 60;
        b.vx = Math.cos(a) * sp; b.vy = Math.sin(a) * sp;
      }
      bs[w++] = b;
    }
    bs.length = w;
  }
  // 範囲攻撃を進める
  const mo = mouth(e);
  for (const z of d.zones) {
    z.t += 1;
    if (z.shape === Shape.Ring) {
      if (z.t < 4) { z.x = mo.x; z.y = mo.y; }
      z.r += z.vr;
    } else if (z.shape === Shape.Safe) {
      for (const c of z.safe) {
        c.x += c.vx;
        if (c.x < 50 || c.x > W - 50) c.vx = -c.vx;
      }
    } else if (z.shape === Shape.Beam) {
      z.x = mo.x; z.y = mo.y;
      if (z.track > 0) {
        let dd = Math.atan2(e.py() - mo.y, e.px() - mo.x) - z.a;
        while (dd > Math.PI) dd -= 2 * Math.PI;
        while (dd < -Math.PI) dd += 2 * Math.PI;
        z.a += Math.min(z.track, Math.max(-z.track, dd));
      }
    }
  }
  d.zones = d.zones.filter((z) => !(z.t >= z.warn + z.dur || (z.shape === Shape.Ring && z.r > 760)));
  if (d.pull === 2 && !e.bullets().some((b) => b.script === DRAGON_TORNADO)) d.pull = 0;
}

/** 引き寄せ先(アプリの dragonPullTarget) */
function pullTarget(e: DragonEnv): { x: number; y: number } | null {
  if (e.d.pull === 1) return mouth(e);
  let best: { x: number; y: number } | null = null, bd = Infinity;
  for (const b of e.bullets()) {
    if (b.script !== DRAGON_TORNADO) continue;
    const dx = b.x - e.px(), dy = b.y - e.py(), dd = dx * dx + dy * dy;
    if (dd < bd) { bd = dd; best = { x: b.x, y: b.y }; }
  }
  return best;
}

/** 自機を流す・引き寄せる(毎ステップ。アプリの dragonPushPlayer) */
export function dragonPushPlayer(e: DragonEnv) {
  const d = e.d;
  let x = e.px(), y = e.py();
  x += d.windX * 0.5; y += d.windY * 0.5;
  if (d.pull !== 0) {
    const o = pullTarget(e);   // 竜巻は、流される前の自機の位置からいちばん近いもの(アプリと同じ)
    if (o) {
      const dx = o.x - x, dy = o.y - y, l = Math.sqrt(dx * dx + dy * dy);
      if (l > 30) { x += dx / l * d.pullForce * 0.5; y += dy / l * d.pullForce * 0.5; }
    }
  }
  e.setPlayer(Math.min(Math.max(x, 6), W - 6), Math.min(Math.max(y, 6), H - 6));
}

/** 自機の弾を口へ吸い込む。食べたら true(アプリの dragonAbsorb) */
export function dragonAbsorb(e: DragonEnv, s: { x: number; y: number; vx: number; vy: number }): boolean {
  const m = mouth(e);
  const a = Math.atan2(m.y - s.y, m.x - s.x);
  s.vx += (Math.cos(a) * 360 - s.vx) * ABSORB_LERP;
  s.vy += (Math.sin(a) * 360 - s.vy) * ABSORB_LERP;
  const dx = m.x - s.x, dy = m.y - s.y;
  if (dx * dx + dy * dy < 16 * 16) { e.d.eaten += 1; return true; }
  return false;
}

export function tailTip(z: Zone): number {
  const u = (z.t - z.warn) / Math.max(1, z.dur);
  const x = -60 + u * (W + TAIL_LEN + 80);
  return z.sweep > 0 ? x : W - x;
}

/** 範囲攻撃が自機に当たっているか(アプリの dragonZoneHits) */
export function zoneHits(z: Zone, px: number, py: number): boolean {
  if (!(z.t > z.warn)) return false;
  switch (z.shape) {
    case Shape.Rect: {
      let h = px > z.x && px < z.x + z.w && py > z.y && py < z.y + z.h;
      if (h && z.sweep !== 0) {
        const tip = tailTip(z), dd = z.sweep;
        h = dd * (tip + dd * 40 - px) > 0 && dd * (px - (tip - dd * TAIL_LEN)) > 0;
      }
      return h;
    }
    case Shape.Circle: { const dx = px - z.x, dy = py - z.y; return dx * dx + dy * dy < z.r * z.r; }
    case Shape.Safe: return !z.safe.some((c) => { const dx = px - c.x, dy = py - c.y; return dx * dx + dy * dy < c.r * c.r; });
    case Shape.Ring: {
      const dx = px - z.x, dy = py - z.y, q = Math.sqrt(dx * dx + dy * dy);
      return Math.abs(q - z.r) < z.th / 2 && angDiff(Math.atan2(dy, dx), z.gapA) > z.gapW;
    }
    case Shape.Beam: {
      const ux = Math.cos(z.a), uy = Math.sin(z.a), ox = px - z.x, oy = py - z.y, pr = ox * ux + oy * uy;
      return pr > 0 && pr < z.len && Math.abs(ox * uy - oy * ux) < z.w / 2;
    }
  }
  return false;
}

/** 予告が終わる瞬間の、安全な輪の x */
export function safeEnd(c: Safe, warn: number): number {
  let x = c.x, vx = c.vx;
  for (let i = 0; i <= warn; i++) {
    x += vx;
    if (x < 50 || x > W - 50) vx = -vx;
  }
  return x;
}

// ---- 技(アプリの runDragonMove と同じ。null = 終わり、0 = 続ける、n > 0 = n フレーム後、-1 = 本体の移動が終わったら) ----
function runMove(e: DragonEnv, m: number): boolean {
  for (;;) {
    let r: number | null;
    switch (m) {
      case 0: r = breath(e); break;
      case 1: r = raid(e); break;
      case 2: r = gale(e); break;
      case 3: r = inhale(e); break;
      case 4: r = glideMove(e); break;
      case 5: r = roar(e); break;
      case 6: r = quake(e); break;
      case 7: r = tail(e); break;
      case 8: r = rampage(e); break;
      default: r = megido(e); break;
    }
    if (r === null) return false;
    if (r === 0) continue;
    if (r < 0) return true;
    e.d.resumeAt = e.d.frame + r;
    return true;
  }
}

function breath(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c0 = 0; d.pc = 1; return 0;
    case 1: {
      if (d.c0 >= dv(L, 1, 1, 1, 2)) { d.pc = 9; return 20; }
      const o = mouth(e);
      const dur = dv(L, 150, 160, 160, 150), warn = d.c0 > 0 ? 30 : 44;
      const z = zoneOf(Shape.Beam, {});
      z.x = o.x; z.y = o.y;
      z.a = aimFrom(e, o) + (e.px() < W / 2 ? 0.45 : -0.45);
      z.w = dv(L, 78, 96, 106, 124);
      z.warn = warn; z.dur = dur;
      z.track = dv(L, 0.0041, 0.0046, 0.0050, 0.0057);
      addZone(e, z);
      d.c1 = d.zones[d.zones.length - 1]!.id;
      d.c2 = 0; d.c3 = warn + dur;
      d.pc = 2; return 0;
    }
    case 2: {
      const t = d.c2;
      if (t >= d.c3) { d.pc = 3; return 24; }
      const warn = d.c0 > 0 ? 30 : 44;
      const z = d.zones.find((q) => q.id === d.c1);
      if (t > warn + 6 && t % dv(L, 13, 11, 9, 8) === 0 && z) {
        const mo = mouth(e);
        const dd = 150 + e.rng() * 380;
        const x = mo.x + Math.cos(z.a) * dd + (e.rng() - 0.5) * 30, y = mo.y + Math.sin(z.a) * dd;
        if (y < H - 10 && x > 10 && x < W - 10) fire(e, "flame", x, y, -Math.PI / 2, 0.15, dv(L, 8, 8, 9, 10), dv(L, 110, 120, 130, 140));
      }
      d.c2 = t + 1;
      return 1;
    }
    case 3: d.c0 += 1; d.pc = 1; return 0;
    default: return null;
  }
}

function raid(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c0 = 0; d.pc = 1; return 0;
    case 1: {
      if (d.c0 >= dv(L, 2, 3, 3, 4)) { d.pc = 99; return 30; }
      const tx = clamp(e.px(), 70, W - 70), ty = clamp(e.py() - 95, 150, H - 180);
      const ap = dv(L, 26, 19, 15, 14), w1 = 10 + ap + 6;
      d.d0 = tx; d.d1 = ty; d.c1 = ap;
      const cx = dv(L, 30, 24, 20, 18), cy = ty + dv(L, 64, 76, 80, 82), cr = dv(L, 66, 81, 86, 88);
      addZone(e, zoneOf(Shape.Circle, { x: tx + cx, y: cy, r: cr, warn: w1, dur: 8 }));
      addZone(e, zoneOf(Shape.Circle, { x: tx - cx, y: cy, r: cr, warn: w1 + 20, dur: 8 }));
      if (L >= 2) addZone(e, zoneOf(Shape.Circle, { x: tx, y: ty + 85, r: dv(L, 0, 0, 100, 116), warn: w1 + 44, dur: 14 }));
      d.pc = 2; return 10;
    }
    case 2: {
      const ap = d.c1;
      bodyHit(e, ap + (L >= 2 ? 90 : 66), 44);
      glideTo(e, d.d0, d.d1, ap);
      d.c2 = 1;
      d.pc = 3; return -1;
    }
    case 3: d.pc = 4; return 6;
    case 4: {
      const side = d.c2 === 1;
      const h = hand(e, side), dir = side ? -1 : 1, n = dv(L, 3, 5, 6, 7);
      for (let k = 0; k < n; k++) {
        const a = Math.PI / 2 + dir * (0.25 + k * 1.3 / n);
        fire(e, "slash", h.x, h.y, a, 4.4 + k * 0.3, 10);
      }
      d.pc = 5; return 14;
    }
    case 5:
      if (d.c2 === 1) { d.c2 = 0; d.pc = 3; return 0; }
      d.pc = 6;
      return L >= 2 ? 28 : 0;
    case 6: glideOffset(e, 0, 0, dv(L, 30, 26, 24, 20)); d.pc = 7; return -1;
    case 7: d.pc = 8; return dv(L, 10, 8, 6, 4);
    case 8: d.c0 += 1; d.pc = 1; return 0;
    default: return null;
  }
}

function gale(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c3 = e.rng() < 0.5 ? 1 : -1; d.c0 = 0; d.pc = 1; return 0;
    case 1: {
      if (d.c0 >= dv(L, 4, 6, 7, 8)) { d.pc = 99; return 40; }
      d.c3 = L >= 1 ? (e.rng() < 0.5 ? 1 : -1) : -d.c3;
      d.pc = 2; return dv(L, 26, 24, 22, 20);
    }
    case 2: {
      const dir = d.c3;
      d.windX = dir * dv(L, 1.5, 2.2, 2.7, 3.0); d.windY = dv(L, 0.5, 0.6, 0.8, 1.0);
      d.c1 = 0; d.pc = 3; return 0;
    }
    case 3: {
      if (d.c1 >= dv(L, 3, 8, 10, 12)) { d.pc = 4; return 0; }
      const dir = d.c3;
      const y = 240 + e.rng() * (H - 270);
      const s = dv(L, 3.4, 4.3, 4.9, 5.3) + e.rng();
      fire(e, "gust", dir > 0 ? -20 : W + 20, y, dir > 0 ? 0 : Math.PI, s, dv(L, 11, 12, 13, 14));
      d.c1 += 1;
      return dv(L, 12, 8, 7, 6);
    }
    case 4: {
      for (const side of [false, true]) {
        const o = wing(e, side);
        for (const dd of L >= 2 ? [-0.3, 0, 0.3] : [0]) fire(e, "gust", o.x, o.y, aimFrom(e, o) + dd, dv(L, 3.2, 3.6, 3.8, 4.0), 9);
      }
      d.pc = 5; return 14;
    }
    case 5: d.windX = 0; d.windY = 0; d.c0 += 1; d.pc = 1; return 0;
    default: return null;
  }
}

function inhale(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0:
      d.pull = 1; d.pullForce = dv(L, 0.7, 1.0, 1.3, 1.6);
      d.absorbing = true; d.eaten = 0;
      d.c1 = 0; d.pc = 1; return 0;
    case 1: {
      const t = d.c1;
      if (t >= 130) { d.pull = 0; d.pullForce = 0; d.absorbing = false; d.c0 = 0; d.pc = 2; return 0; }
      if (t % 10 === 0) {
        const side = e.rng(), x = side < 0.5 ? -6 : W + 6, y = 240 + e.rng() * 200;
        fire(e, "ember", x, y, 0, 0, 3, 0, DRAGON_EMBER);
      }
      d.c1 = t + 1;
      return 1;
    }
    case 2: {
      if (d.c0 >= dv(L, 1, 2, 3, 3)) { d.c1 = 0; d.pc = 3; return 0; }
      const mo = mouth(e), tx = e.px(), ty = e.py();
      const rr = dv(L, 140, 154, 160, 168);
      const fl = Math.round(rr / 3.3) + dv(L, 26, 20, 16, 13);
      addZone(e, zoneOf(Shape.Circle, { x: tx, y: ty, r: rr, warn: fl, dur: 26 }));
      const bs = e.bullets();
      if (bs.length < e.maxBullets) {
        const b = blank(mo.x, mo.y);
        b.look = 16 + KIND.sun * 2 + (L > 0 ? 1 : 0);
        b.script = DRAGON_SUN; b.radius = 26; b.fuse = fl / 60;
        b.u0 = mo.x; b.u1 = mo.y; b.u2 = tx; b.u3 = ty;
        bs.push(b);
      }
      d.c0 += 1;
      return fl + dv(L, 40, 20, 18, 12);
    }
    case 3: {
      const back = Math.min(d.eaten, dv(L, 24, 36, 48, 60));
      if (d.c1 >= back) { d.pc = 99; return 40; }
      const mo = mouth(e), i = d.c1;
      for (const dd of L >= 3 ? [-0.25, 0, 0.25] : [0]) fire(e, "pshot", mo.x, mo.y, aimFrom(e, mo) + dd + Math.sin(i * 0.9) * 0.5, dv(L, 3.6, 4.2, 4.8, 5.4), 3);
      d.c1 += 1;
      return dv(L, 4, 3, 2, 2);
    }
    default: return null;
  }
}

function glideMove(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: glideOffset(e, 0, -340, 26); d.c0 = 0; d.pc = 1; return -1;
    case 1: {
      if (d.c0 >= dv(L, 3, 4, 5, 6)) { glideOffset(e, 0, 0, 30); d.pc = 5; return -1; }
      const dir = d.c0 % 2 === 1 ? -1 : 1;
      const hh = dv(L, 100, 124, 136, 148), y0 = e.py() - hh / 2;
      const warn = dv(L, 48, 35, 35, 34), n = dv(L, 36, 34, 30, 28);
      addZone(e, zoneOf(Shape.Rect, { x: 0, y: y0, w: W, h: hh, warn, dur: n }));
      d.c3 = dir; d.d0 = y0; d.d1 = hh; d.c2 = n; d.c1 = 0;
      d.pc = 2; return warn;
    }
    case 2: d.pose = d.c3; d.pc = 3; return 0;
    case 3: {
      const i = d.c1, n = d.c2, dir = d.c3;
      if (i >= n) { d.pose = 0; d.boffX = 0; d.boffY = -340; d.pc = 4; return dv(L, 18, 10, 8, 6); }
      const span = (W + 520) / n;
      const x = dir > 0 ? -260 + i * span : W + 260 - i * span;
      const base = e.base();
      d.boffX = x + dir * 20 - base.x; d.boffY = d.d0 + d.d1 / 2 - 24 - base.y;
      if (i % dv(L, 4, 3, 2, 2) === 0 && x > 10 && x < W - 10) {
        const a = Math.PI / 2 + (e.rng() - 0.5) * 0.3;
        const s = dv(L, 1.6, 1.9, 2.2, 2.5) + e.rng();
        fire(e, "flame", x, d.d0 + d.d1 / 2 + 16, a, s, 8, 90);
      }
      d.c1 = i + 1;
      return 1;
    }
    case 4: d.c0 += 1; d.pc = 1; return 0;
    case 5: d.pc = 99; return 20;
    default: return null;
  }
}

function roar(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c0 = 0; d.pc = 1; return 0;
    case 1: {
      if (d.c0 >= dv(L, 3, 5, 6, 7)) { d.pc = 99; return 70; }
      const mo = mouth(e);
      const base = aimFrom(e, mo);
      const sgn = e.rng() < 0.5 ? 1 : -1;
      const gapA = base + sgn * (0.3 + e.rng() * 0.25);
      const z = zoneOf(Shape.Ring, { x: mo.x, y: mo.y, r: 10, warn: 0, dur: 200 });
      z.vr = dv(L, 2.6, 2.9, 3.0, 3.4); z.th = dv(L, 16, 16, 18, 20);
      z.gapA = gapA; z.gapW = dv(L, 0.55, 0.50, 0.49, 0.42);
      z.bind = dv(L, 80, 85, 95, 110);
      addZone(e, z);
      d.pc = 2; return dv(L, 34, 32, 30, 28);
    }
    case 2: {
      const v = d.c0;
      if (v % 2 === 1 || L >= 2) {
        const o = mouth(e);
        for (const dd of L >= 3 && v % 2 === 1 ? [-0.22, 0.22] : [0]) fire(e, "sun", o.x, o.y, aimFrom(e, o) + dd, 3.0 + L * 0.15, 16, 0, DRAGON_PLAIN, 0, true);
      }
      d.c0 += 1; d.pc = 1;
      return dv(L, 26, 24, 22, 20);
    }
    default: return null;
  }
}

function quake(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c0 = 0; d.pc = 1; return 0;
    case 1: {
      if (d.c0 >= dv(L, 2, 3, 4, 5)) { d.pc = 99; return 40; }
      const warn = dv(L, 46, 38, 34, 30);
      d.cracks = [];
      const x0 = clamp(e.px() + (e.rng() - 0.5) * 80, 40, W - 40);
      const starts = [x0];
      if (L >= 2) starts.push(x0 + (x0 < W / 2 ? 1 : -1) * (110 + e.rng() * 40));
      for (const sx of starts) {
        const pts: { x: number; y: number }[] = [];
        let x = clamp(sx, 30, W - 30);
        let y = 150;
        while (y <= H + 20) {
          pts.push({ x, y });
          const sgn = e.rng() < 0.5 ? -1 : 1;
          x = clamp(x + sgn * (30 + e.rng() * 40), 30, W - 30);
          y += 50;
        }
        d.cracks.push(pts);
      }
      d.pc = 2; return warn;
    }
    case 2: {
      const r = dv(L, 22, 26, 30, 34);
      for (const pts of d.cracks) {
        for (let i = 0; i < pts.length - 1; i++) {
          for (let k = 0; k < 2; k++) {
            const a = pts[i]!, b = pts[i + 1]!, f = k / 2;
            addZone(e, zoneOf(Shape.Circle, { x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, r, warn: i * 2, dur: dv(L, 46, 50, 54, 58) }));
          }
        }
        for (let k = 0; k < dv(L, 4, 7, 7, 9); k++) {
          const q = pts[1 + Math.trunc(e.rng() * (pts.length - 2))]!;
          const a = -Math.PI / 2 + (e.rng() - 0.5) * 1.4;
          const s = dv(L, 3.0, 3.4, 3.8, 4.2) + e.rng() * 2;
          fire(e, "rock", q.x, q.y, a, s, 8, 0, DRAGON_PLAIN, 0.07);
        }
      }
      d.c0 += 1; d.pc = 1;
      return dv(L, 64, 50, 44, 38);
    }
    default: return null;
  }
}

function tail(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c0 = 0; d.pc = 1; return 0;
    case 1:
      if (d.c0 >= dv(L, 3, 4, 4, 5)) { d.pc = 99; return 50; }
      d.c2 = d.c0 % 2 === 1 ? -1 : 1;
      d.c3 = 0;
      d.pc = 10; return 0;
    case 10: {
      const hh = dv(L, 80, 112, 120, 132), y0 = e.py() - hh / 2, dur = dv(L, 38, 34, 30, 27);
      const warn = d.c3 === 0 ? dv(L, 34, 23, 26, 24) : dv(L, 0, 0, 32, 30);
      addZone(e, zoneOf(Shape.Rect, { x: 0, y: y0, w: W, h: hh, warn, dur, sweep: d.c2 }));
      d.d0 = y0 + hh / 2;
      d.pc = 11;
      return warn + Math.round(dur * 0.4);
    }
    case 11: {
      const n = dv(L, 7, 9, 12, 14);
      const sx0 = e.rng() * (W / n);
      for (let k = 0; k < n; k++) {
        const x = sx0 + k * W / n;
        fire(e, "spine", x, d.d0, k % 2 === 1 ? Math.PI / 2 : -Math.PI / 2, dv(L, 2.3, 2.8, 3.2, 3.6), 6);
      }
      if (d.c3 === 0 && L >= 2) { d.c3 = 1; d.c2 = -d.c2; d.pc = 10; return 0; }
      d.pc = 12;
      return dv(L, 50, 40, 30, 24);
    }
    case 12: d.c0 += 1; d.pc = 1; return 0;
    default: return null;
  }
}

function rampage(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  const T = dv(L, 210, 250, 280, 300);
  switch (d.pc) {
    case 0:
      bodyHit(e, T + 20, dv(L, 40, 44, 48, 52));
      d.c1 = 0; d.d0 = 0;
      d.pc = 1; return 0;
    case 1: {
      const t = d.c1;
      if (t >= T) { d.boffX = 0; d.boffY = 0; d.pc = 2; return 120; }
      const u = t / T * 2 * Math.PI * dv(L, 1.5, 2, 2.6, 3.2);
      const ee = Math.min(1, t / 30, (T - t) / 30);
      const b = bossPos(e);
      d.d0 += (clamp(e.px() - 180, -90, 90) * dv(L, 0, 0.4, 0.7, 0.9) - d.d0) * 0.03;
      d.boffX = (Math.sin(u * 2) * dv(L, 110, 120, 130, 140) + d.d0) * ee;
      d.boffY = (0.5 - 0.5 * Math.cos(u)) * dv(L, 288, 306, 324, 346) * ee;
      const at = dv(L, [60, 130], [50, 110, 170], [40, 95, 150, 205], [30, 80, 130, 180, 230]);
      const bs = e.bullets();
      if (at.includes(t) && bs.length < e.maxBullets) {
        const q = blank(b.x, b.y + 40);
        q.look = 16 + KIND.tornado * 2 + (L > 0 ? 1 : 0);
        q.script = DRAGON_TORNADO;
        q.radius = dv(L, 22, 22, 24, 26);
        q.homeLeft = dv(L, 50, 50, 60, 70);
        q.fuse = 260 / 60;
        q.u0 = clamp(b.x, 60, W - 60); q.u1 = clamp(b.y + 60, 280, H - 80); q.u2 = e.rng() * 9;
        bs.push(q);
      }
      if (e.bullets().some((x) => x.script === DRAGON_TORNADO)) { d.pull = 2; d.pullForce = dv(L, 0.6, 0.9, 1.15, 1.4); }
      else d.pull = 0;
      if (t % dv(L, 16, 12, 9, 7) === 0) {
        const a = Math.PI / 2 + (e.rng() - 0.5) * 0.8;
        fire(e, "flame", b.x, b.y + 30, a, dv(L, 1.4, 1.8, 2.2, 2.6), 8);
      }
      d.c1 = t + 1;
      return 1;
    }
    case 2: d.pull = 0; return null;
    default: return null;
  }
}

function megido(e: DragonEnv): number | null {
  const d = e.d, L = d.lv;
  switch (d.pc) {
    case 0: d.c0 = 0; d.pc = 1; return 0;
    case 1: {
      if (d.c0 >= dv(L, 2, 2, 3, 3)) { d.pc = 99; return 40; }
      const n = dv(L, 2, 1, 1, 1), sp = dv(L, 0, 0.5, 0.8, 1.1);
      const warn = dv(L, 115, 100, 92, 85), reach = 3.3 * (warn - 30), far = dv(L, 60, 80, 100, 110);
      const cr = dv(L, 46, 40, 36, 32);
      const safe: Safe[] = [];
      for (let k = 0; k < n; k++) {
        let c: Safe = { x: 0, y: 0, r: cr, vx: 0 };
        let tries = 0;
        do {
          c = { x: 60 + e.rng() * (W - 120), y: 300 + e.rng() * (H - 360), r: cr, vx: 0 };
          c.vx = sp * (e.rng() < 0.5 ? 1 : -1);
          const ex = safeEnd(c, warn);
          const dd = Math.sqrt((ex - e.px()) * (ex - e.px()) + (c.y - e.py()) * (c.y - e.py())) - (c.r - 14);
          const ok = k === 0 ? (dd <= reach && dd >= far)
            : !safe.some((o) => Math.sqrt((o.x - c.x) * (o.x - c.x) + (o.y - c.y) * (o.y - c.y)) < 130);
          if (ok) break;
          tries += 1;
        } while (tries < 60);
        if (k === 0 && tries >= 60) { c.x = clamp(e.px(), 60, W - 60); c.y = clamp(e.py(), 300, H - 60); c.vx = 0; }
        safe.push(c);
      }
      const z = zoneOf(Shape.Safe, { warn, dur: 22 });
      z.kill = true;
      z.safe = safe;
      addZone(e, z);
      d.c1 = 0; d.c2 = warn;
      d.pc = 2; return 0;
    }
    case 2: {
      const t = d.c1, warn = d.c2;
      if (t >= warn + dv(L, 60, 50, 40, 34)) { d.c0 += 1; d.pc = 1; return 0; }
      if (L >= 1 && t < warn - 20 && t > 4 && t % dv(L, 1, 9, 6, 4) === 0) {
        const x = 20 + e.rng() * (W - 40), y = 150 + e.rng() * 60;
        const a = Math.PI / 2 + (e.rng() - 0.5) * 0.2;
        fire(e, "flame", x, y, a, dv(L, 0, 3.6, 4.2, 4.8), 9, 260, DRAGON_DROP);
      }
      if (t === warn) e.setBullets(e.bullets().filter((b) => b.script !== DRAGON_DROP));
      d.c1 = t + 1;
      return 1;
    }
    default: return null;
  }
}

export { INV as DRAGON_INV, KIND as DRAGON_KIND, dv as dragonDv, zoneOf as dragonZoneOf };
