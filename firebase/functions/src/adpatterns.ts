// このファイルは tools/gen_ad_patterns.py が生成する。直接は編集しない(表を直してスクリプトを実行し直す)。
// 広告で解放する34パターンの、弾の出し方。アプリ(AdPatterns.swift)と同じ表と計算。

export interface Recipe {
  mode: number;
  fan: number;
  spin: number;
  sweepAmp: number;
  sweepFreq: number;
  layers: number;
  layerAngle: number;
  layerSpeed: number;
  wobbleAmp: number;
  wobbleFreq: number;
  wobblePhase: number;
  waveAmp: number;
  waveFreq: number;
  wavePhase: number;
  speedStep: number;
  speedCycle: number;
  altSpeed: number;
  speed0: number;
  lineWidth: number;
  scatter: number;
  jitter: number;
  turn: number;
  accel: number;
  maxMul: number;
  bounces: number;
  script: number;
  beam: number;
  beamSweep: number;
  beamTime: number;
  curve: number;
  curveTime: number;
  giant: number;
}

const BASE: Recipe = { mode: 0, fan: 0, spin: 1, sweepAmp: 0, sweepFreq: 0.25, layers: 1, layerAngle: 0, layerSpeed: 1, wobbleAmp: 0, wobbleFreq: 1, wobblePhase: 0, waveAmp: 0, waveFreq: 1, wavePhase: 0, speedStep: 0, speedCycle: 0, altSpeed: 0, speed0: 1, lineWidth: 0, scatter: 0, jitter: 0, turn: 0, accel: 0, maxMul: 0, bounces: 0, script: 0, beam: 0, beamSweep: 0, beamTime: 0, curve: 0, curveTime: 0, giant: 0 };

export const AD_PATTERNS = ["twinRing", "tripleRing", "pinwheel", "ripple", "chargeBeam", "whirl", "slither", "curtain", "swayFan", "boomerang", "drizzle", "comet", "shotgun", "sniper", "giantOrb", "twinAim", "zigzagAim", "accelRing", "homingRing", "sweepLaser", "bounceRing", "freezeRing", "shatterRing", "pulseRing", "freezeCurtain", "splitCurtain", "wavyRing", "petalFan", "waveSpiral", "tide", "ladder", "helix", "rapidFan", "lightRain"] as const;

export const RECIPES: Record<string, Recipe> = {
  twinRing: { ...BASE, mode: 0, layers: 2, layerSpeed: 0.6 },
  tripleRing: { ...BASE, mode: 0, layers: 3, layerSpeed: 0.75 },
  pinwheel: { ...BASE, mode: 0, altSpeed: 0.45 },
  ripple: { ...BASE, mode: 0, spin: 0, layers: 4, layerAngle: 5, layerSpeed: 0.85 },
  chargeBeam: { ...BASE, mode: 1, beam: 1 },
  whirl: { ...BASE, mode: 0, speedStep: 0.035 },
  slither: { ...BASE, mode: 2, wobbleAmp: 22, wobbleFreq: 1.1, wobblePhase: 0.6 },
  curtain: { ...BASE, mode: 2, fan: -1, lineWidth: 330 },
  swayFan: { ...BASE, mode: 2, fan: 70, lineWidth: 280, bounces: 2 },
  boomerang: { ...BASE, mode: 1, curve: 130, curveTime: 1.4 },
  drizzle: { ...BASE, mode: 2, fan: -1, speed0: 0.25, scatter: 340, accel: 1, maxMul: 2.6 },
  comet: { ...BASE, mode: 1, speedStep: 0.15 },
  shotgun: { ...BASE, mode: 1, jitter: 10 },
  sniper: { ...BASE, mode: 2, fan: -1, lineWidth: 300, turn: 30 },
  giantOrb: { ...BASE, mode: 1, fan: -1, bounces: 1, giant: 1 },
  twinAim: { ...BASE, mode: 1, layers: 2, layerSpeed: 0.7, script: 3 },
  zigzagAim: { ...BASE, mode: 1, wobbleAmp: 16, wobbleFreq: 2.3, wobblePhase: 0.9 },
  accelRing: { ...BASE, mode: 0, speed0: 0.35, accel: 0.8, maxMul: 2.2 },
  homingRing: { ...BASE, mode: 0, turn: 40 },
  sweepLaser: { ...BASE, mode: 1, beam: 1, beamSweep: 90, beamTime: 1.2 },
  bounceRing: { ...BASE, mode: 0, bounces: 2 },
  freezeRing: { ...BASE, mode: 0, script: 1 },
  shatterRing: { ...BASE, mode: 0, script: 2 },
  pulseRing: { ...BASE, mode: 2, fan: -1, scatter: 340, script: 1 },
  freezeCurtain: { ...BASE, mode: 2, fan: -1, lineWidth: 300, script: 1 },
  splitCurtain: { ...BASE, mode: 2, fan: -1, lineWidth: 300, script: 2 },
  wavyRing: { ...BASE, mode: 0, waveAmp: 0.35, waveFreq: 3 },
  petalFan: { ...BASE, mode: 1, waveAmp: 0.4, waveFreq: 3 },
  waveSpiral: { ...BASE, mode: 0, waveAmp: 0.3, waveFreq: 1.7, wavePhase: 0.8 },
  tide: { ...BASE, mode: 2, waveAmp: 0.5, waveFreq: 2, wavePhase: 1.3 },
  ladder: { ...BASE, mode: 2, fan: -1, altSpeed: 0.6, lineWidth: 300 },
  helix: { ...BASE, mode: 0, layers: 2, layerAngle: 8, layerSpeed: 1.15 },
  rapidFan: { ...BASE, mode: 1, speedStep: 0.12, speedCycle: 3 },
  lightRain: { ...BASE, mode: 2, fan: -1, speed0: 1.2, scatter: 340, jitter: 3 },
};

/** チャージビームの印(弾の script)。アプリの Bullet.beamScript と同じ */
export const BEAM_SCRIPT = 4;
/** ブーメランと巨大弾の印。アプリの Bullet.boomerangScript / giantScript と同じ */
export const BOOMERANG_SCRIPT = 5, GIANT_SCRIPT = 6;

/** 弾を1つ出す関数(呼ぶ側の Bullet の形に合わせる) */
export type AddBullet = (x: number, y: number, vx: number, vy: number, extra: { turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number }) => void;

export function emitRecipe(r: Recipe, m: { c: number; r: number; k: number }, k: number, cx: number, cy: number, px: number, py: number,
  off: number, sp: number, n: number, rng: () => number, homingSeconds: number, add: AddBullet): void {
  const deg = Math.PI / 180;
  const fanDeg = r.fan < 0 ? 0 : (r.fan > 0 ? r.fan : m.r);
  let layerSpeed = 1;
  for (let layer = 0; layer < Math.max(1, r.layers); layer++) {
    const layerShift = layer * r.layerAngle * deg;
    let base: number;
    if (r.mode === 0) base = k * m.r * deg * r.spin + off;
    else if (r.mode === 1) base = Math.atan2(py - cy, px - cx) + off;
    else base = Math.PI / 2 + off + Math.sin(k * r.sweepFreq) * m.r * deg * r.sweepAmp;
    for (let j = 0; j < n; j++) {
      let a: number;
      if (r.mode === 0) a = base + (j * 2 * Math.PI) / n;
      else a = base + (n > 1 ? (j / (n - 1) - 0.5) * fanDeg * deg : 0);
      a += layerShift;
      if (r.wobbleAmp !== 0) a += r.wobbleAmp * deg * Math.sin(j * r.wobbleFreq + k * r.wobblePhase);
      if (r.jitter !== 0) a += (rng() - 0.5) * 2 * r.jitter * deg;
      let f = r.speed0 * layerSpeed;
      if (r.speedStep !== 0) { const jj = r.speedCycle > 0 ? j % r.speedCycle : j; f *= 1 + jj * r.speedStep; }
      if (r.altSpeed !== 0 && j % 2 === 1) f *= r.altSpeed;
      if (r.waveAmp !== 0) f *= 1 + r.waveAmp * Math.sin(j * r.waveFreq + k * r.wavePhase);
      let x = cx;
      if (r.lineWidth !== 0) x += (n > 1 ? j / (n - 1) - 0.5 : 0) * r.lineWidth;
      if (r.scatter !== 0) x += (rng() - 0.5) * r.scatter;
      const side = j % 2 === 0 ? 1 : -1;
      if (r.beam !== 0) {
        // チャージビーム: その場に止まったまま、向き(長さ1)だけを持つ。アプリの Bullet.beam と同じ
        if (r.beamSweep !== 0) {
          const a0 = a - side * r.beamSweep * deg / 2;
          add(x, cy, Math.cos(a0), Math.sin(a0), { turn: side * r.beamSweep * deg / r.beamTime, homeLeft: r.beamTime, accel: 0, maxSpeed: 0, bounces: 1, script: BEAM_SCRIPT });
        } else {
          add(x, cy, Math.cos(a), Math.sin(a), { turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 1, script: BEAM_SCRIPT });
        }
        continue;
      }
      if (r.curve !== 0) {
        // ブーメラン: 決まった時間だけ向きを回す(追尾ではない)
        add(x, cy, Math.cos(a) * sp * f, Math.sin(a) * sp * f, { turn: side * r.curve * deg, homeLeft: r.curveTime, accel: 0, maxSpeed: 0, bounces: r.bounces, script: BOOMERANG_SCRIPT });
        continue;
      }
      add(x, cy, Math.cos(a) * sp * f, Math.sin(a) * sp * f, {
        turn: r.turn * deg, homeLeft: r.turn > 0 ? homingSeconds : 0, accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces,
        script: r.giant !== 0 ? GIANT_SCRIPT : r.script,
      });
    }
    layerSpeed *= r.layerSpeed;
  }
}
