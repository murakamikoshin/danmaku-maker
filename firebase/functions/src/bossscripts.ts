/**
 * ボスの専用の技が使う、弾の動き(印 = script)。アプリの BossScripts.swift と同じ計算。
 * 数値は engine.js(60fps の px/フレーム)を、秒・px/秒に直したもの。
 */
export const HOLD_SCRIPT = 16, BRANCH_SCRIPT = 17, FREEZE_SCRIPT = 18, WIND_SCRIPT = 19, ORBIT_SCRIPT = 20, DRAG_SCRIPT = 21,
  LATERAL_SCRIPT = 22, CURVE_SCRIPT = 23, MISSILE_SCRIPT = 24, DARK_SCRIPT = 25, WARP = 26;

/** 専用の弾の番号(アプリの BulletLook.code と同じ: 16 + 種類 × 2 + 覚醒) */
export const KIND = { fox: 0, ofuda: 1, plankton: 2, bubble: 3, ink: 4, missile: 5, hex: 6, shell: 7, flake: 8, icicle: 9, shard: 10, soul: 11, blade: 12, chain: 13, jelly: 14, eye: 15, tooth: 16, goo: 17 } as const;
export const lookCode = (kind: number, awakened: boolean): number => 16 + kind * 2 + (awakened ? 1 : 0);
export const lookKind = (look: number | undefined): number | undefined => (look === undefined || look < 16 ? undefined : Math.floor((look - 16) / 2));
export const lookAwakened = (look: number | undefined): boolean => look !== undefined && look >= 16 && (look - 16) % 2 === 1;

const MISSILE_DECAY = Math.sqrt(0.95), DRAG_DECAY = Math.sqrt(0.995), WIND_LERP = 1 - Math.sqrt(0.97), LOCK_LERP = 1 - Math.sqrt(0.88);

export interface BossBullet {
  x: number; y: number; vx: number; vy: number; color: number; turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number; age: number;
  gravity?: number; radius?: number; grow?: number; growMax?: number; fuse?: number; look?: number;
  u0?: number; u1?: number; u2?: number; u3?: number;
}

/** 見えず、当たらない(待機中の弾・暗転の印) */
export const isDormant = (b: { script: number; age: number; fuse?: number }): boolean =>
  ((b.script === HOLD_SCRIPT || b.script === MISSILE_SCRIPT) && b.age < (b.fuse ?? 0)) || b.script === DARK_SCRIPT;

export const plainBullet = (x: number, y: number, vx: number, vy: number, color: number, look: number): BossBullet =>
  ({ x, y, vx, vy, color, turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, age: 0, look });

/** 待機してから動き出す弾を作る(アプリの Emit.holdBullet と同じ) */
export function holdBullet(x: number, y: number, delay: number, speed: number, angle: number, aim: boolean, look: number, color: number, lifetime = 0, gravity = 0): BossBullet {
  const b = plainBullet(x, y, 0, 0, color, look);
  b.script = HOLD_SCRIPT; b.fuse = delay; b.u0 = speed; b.u1 = angle; b.u2 = aim ? 1 : 0; b.u3 = lifetime;
  if (gravity) b.gravity = gravity;
  return b;
}

/** 枝分かれ: 進んでいた向きから ±u1 の2つに分かれる */
export function branchChildren(b: BossBullet): BossBullet[] {
  const sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
  const base = Math.atan2(b.vy, b.vx);
  const left = b.homeLeft - 1;
  const aw = lookAwakened(b.look);
  return [-(b.u1 ?? 0), b.u1 ?? 0].map((d) => {
    const c = plainBullet(b.x, b.y, Math.cos(base + d) * sp, Math.sin(base + d) * sp, b.color, lookCode(left >= 1 ? KIND.shard : KIND.flake, aw));
    if (left >= 1) { c.script = BRANCH_SCRIPT; c.homeLeft = left; c.u0 = b.u0; c.u1 = b.u1; }
    return c;
  });
}

/** 1ステップ進める。alive/gone/burst を返す。null はここでは扱わない(ふつうの動きに進む) */
export function stepBossScript(b: BossBullet, dt: number, px: number, py: number): "alive" | "gone" | "burst" | null {
  switch (b.script) {
    case HOLD_SCRIPT: {
      b.age += dt;
      if (b.age < (b.fuse ?? 0)) return "alive";
      if (b.homeLeft === 0) {
        b.homeLeft = 1;
        const a = b.u2 === 1 ? Math.atan2(py - b.y, px - b.x) + (b.u1 ?? 0) : (b.u1 ?? 0);
        b.vx = Math.cos(a) * (b.u0 ?? 0); b.vy = Math.sin(a) * (b.u0 ?? 0);
        if ((b.u3 ?? 0) <= 0) { b.script = 0; return null; }
      }
      if ((b.u3 ?? 0) > 0 && b.age >= (b.fuse ?? 0) + (b.u3 ?? 0)) return "gone";
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    case BRANCH_SCRIPT:
      b.age += dt;
      if (b.homeLeft >= 1 && b.age >= (b.u0 ?? 0)) return "burst";
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    case FREEZE_SCRIPT:
      b.age += dt;
      if (b.age >= (b.u1 ?? 0)) return "gone";
      if (b.age >= (b.u0 ?? 0)) {
        if (b.vx !== 0 || b.vy !== 0) { b.vx = 0; b.vy = 0; b.look = lookCode(KIND.flake, lookAwakened(b.look)); }
        return "alive";
      }
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    case WIND_SCRIPT: {
      b.age += dt;
      const u2 = b.u2 ?? 0;
      const n = b.age < u2 ? 0 : 1 + Math.floor((b.age - u2) / 2);
      const w = n % 2 === 0 ? (b.u0 ?? 0) : -(b.u0 ?? 0);
      b.vx += (w - b.vx) * WIND_LERP;
      b.vy = ((b.u3 ?? 0) > 0 ? (b.u3 ?? 0) : 96) + Math.sin(b.age * 60 * 0.05 + (b.u1 ?? 0)) * 18;
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    case ORBIT_SCRIPT: {
      b.age += dt;
      if (b.age < (b.fuse ?? 0)) {
        const r = 10 + 72 * b.age, a = (b.u2 ?? 0) + (b.u3 ?? 0) * b.age;
        b.x = (b.u0 ?? 0) + Math.cos(a) * r; b.y = (b.u1 ?? 0) + Math.sin(a) * r;
        return "alive";
      }
      const a = Math.atan2(py - b.y, px - b.x);
      b.vx = Math.cos(a) * 84; b.vy = Math.sin(a) * 84;
      b.turn = 1.5; b.homeLeft = 2.0;
      b.script = 0;
      return null;
    }
    case DRAG_SCRIPT:
      b.age += dt;
      if (b.age >= (b.fuse ?? 0)) return "gone";
      b.vx *= DRAG_DECAY; b.vy *= DRAG_DECAY;
      if (b.grow) b.radius = Math.min(b.growMax ?? 0, (b.radius ?? 0) + b.grow * dt);
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    case LATERAL_SCRIPT: {
      b.age += dt;
      const u0 = b.u0 ?? 0;
      const lat = Math.cos(6 * b.age + (b.u1 ?? 0)) * (b.u2 ?? 0);
      b.vx = Math.cos(u0) * (b.u3 ?? 0) - Math.sin(u0) * lat;
      b.vy = Math.sin(u0) * (b.u3 ?? 0) + Math.cos(u0) * lat;
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    case CURVE_SCRIPT: {
      b.age += dt;
      const sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
      const na = Math.atan2(b.vy, b.vx) + (b.u0 ?? 0) * dt;
      b.vx = Math.cos(na) * sp; b.vy = Math.sin(na) * sp;
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    case MISSILE_SCRIPT: {
      b.age += dt;
      if (b.age < (b.fuse ?? 0)) return "alive";
      const t = b.age - (b.fuse ?? 0);
      let sp = Math.sqrt(b.vx * b.vx + b.vy * b.vy);
      if (t < (b.u0 ?? 0)) {
        b.vx *= MISSILE_DECAY; b.vy *= MISSILE_DECAY;
      } else if (t < (b.u2 ?? 0)) {
        const want = Math.atan2(py - b.y, px - b.x);
        const cur = Math.atan2(b.vy, b.vx);
        let diff = want - cur;
        while (diff > Math.PI) diff -= 2 * Math.PI;
        while (diff < -Math.PI) diff += 2 * Math.PI;
        const maxTurn = b.turn * dt;
        const na = cur + Math.min(maxTurn, Math.max(-maxTurn, diff));
        if ((b.u3 ?? 0) > 0) sp = Math.min(b.maxSpeed, sp + (b.u3 ?? 0) * dt);
        b.vx = Math.cos(na) * sp; b.vy = Math.sin(na) * sp;
      }
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    case DARK_SCRIPT:
      b.age += dt;
      return b.age >= (b.fuse ?? 0) ? "gone" : "alive";
    case WARP: {
      b.age += dt;
      if (b.homeLeft === 0 && b.age >= (b.fuse ?? 0) - 0.5) {
        b.u2 = Math.min(360 - 8, Math.max(8, px + Math.cos(b.u0 ?? 0) * (b.u1 ?? 0)));
        b.u3 = Math.min(540 - 8, Math.max(8, py + Math.sin(b.u0 ?? 0) * (b.u1 ?? 0)));
        b.homeLeft = 1;
      }
      if (b.homeLeft === 1 && b.age >= (b.fuse ?? 0)) { b.x = b.u2 ?? 0; b.y = b.u3 ?? 0; b.homeLeft = 2; }
      b.x += b.vx * dt; b.y += b.vy * dt;
      return "alive";
    }
    default:
      return null;
  }
}

/** ビームの照準(ためている間、自機のほうへなめらかに向きを合わせる) */
export function lockBeam(b: BossBullet, px: number, py: number) {
  const want = Math.atan2(py - b.y, px - b.x);
  const cur = Math.atan2(b.vy, b.vx);
  let diff = want - cur;
  while (diff > Math.PI) diff -= 2 * Math.PI;
  while (diff < -Math.PI) diff += 2 * Math.PI;
  const na = cur + diff * LOCK_LERP;
  b.vx = Math.cos(na); b.vy = Math.sin(na);
}
