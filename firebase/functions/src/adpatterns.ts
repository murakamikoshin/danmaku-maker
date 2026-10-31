// このファイルは tools/gen_ad_patterns.py が生成する。直接は編集しない(表を直してスクリプトを実行し直す)。
// 広告で解放するパターンと、弾幕パック2のパターンの、弾の出し方。アプリ(AdPatterns.swift)と同じ表と計算。

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
  radius: number;
  grow: number;
  growMax: number;
  gravity: number;
  mine: number;
  travel: number;
  fuse: number;
  meteor: number;
  blastRadius: number;
  meteorGap: number;
  grid: number;
  gridGap: number;
  orbitRadius: number;
  trail: number;
  speedJitter: number;
  curveSame: number;
  layerFlip: number;
  weave: number;
  weaveTurn: number;
  weavePeriod: number;
}

const BASE: Recipe = { mode: 0, fan: 0, spin: 1, sweepAmp: 0, sweepFreq: 0.25, layers: 1, layerAngle: 0, layerSpeed: 1, wobbleAmp: 0, wobbleFreq: 1, wobblePhase: 0, waveAmp: 0, waveFreq: 1, wavePhase: 0, speedStep: 0, speedCycle: 0, altSpeed: 0, speed0: 1, lineWidth: 0, scatter: 0, jitter: 0, turn: 0, accel: 0, maxMul: 0, bounces: 0, script: 0, beam: 0, beamSweep: 0, beamTime: 0, curve: 0, curveTime: 0, giant: 0, radius: 0, grow: 0, growMax: 0, gravity: 0, mine: 0, travel: 0, fuse: 0, meteor: 0, blastRadius: 0, meteorGap: 0, grid: 0, gridGap: 0, orbitRadius: 0, trail: 0, speedJitter: 0, curveSame: 0, layerFlip: 0, weave: 0, weaveTurn: 0, weavePeriod: 0 };

export const AD_PATTERNS = ["twinRing", "tripleRing", "pinwheel", "ripple", "chargeBeam", "whirl", "slither", "curtain", "swayFan", "boomerang", "drizzle", "comet", "shotgun", "sniper", "twinAim", "zigzagAim", "accelRing", "bounceRing", "freezeRing", "pulseRing", "freezeCurtain", "splitCurtain", "wavyRing", "petalFan", "waveSpiral", "tide", "ladder", "helix", "rapidFan", "lightRain"] as const;
export const PACK2_PATTERNS = ["mine", "meteor", "gridLaser", "sweepLaser", "giantOrb", "bubble", "gravity", "orbit", "snake", "shatterRing", "homingRing"] as const;

export const RECIPES: Record<string, Recipe> = {
  twinRing: { ...BASE, mode: 0, layers: 2, layerSpeed: 0.6 },
  tripleRing: { ...BASE, mode: 0, curve: 200, curveTime: 0.9, curveSame: 1 },
  pinwheel: { ...BASE, mode: 0, altSpeed: 0.45 },
  ripple: { ...BASE, mode: 0, spin: 0, layers: 4, layerAngle: 5, layerSpeed: 0.85 },
  chargeBeam: { ...BASE, mode: 1, beam: 1 },
  whirl: { ...BASE, mode: 0, speedStep: 0.035 },
  slither: { ...BASE, mode: 2, weave: 1, weaveTurn: 160, weavePeriod: 0.8 },
  curtain: { ...BASE, mode: 2, fan: -1, lineWidth: 330 },
  swayFan: { ...BASE, mode: 2, fan: 70, lineWidth: 280, bounces: 2 },
  boomerang: { ...BASE, mode: 1, curve: 130, curveTime: 1.4 },
  drizzle: { ...BASE, mode: 2, fan: -1, speed0: 0.25, scatter: 340, accel: 1, maxMul: 2.6 },
  comet: { ...BASE, mode: 1, speedStep: 0.15 },
  shotgun: { ...BASE, mode: 1, jitter: 12, speedJitter: 0.45 },
  sniper: { ...BASE, mode: 2, fan: -1, lineWidth: 300, turn: 30 },
  giantOrb: { ...BASE, mode: 1, fan: -1, bounces: 1, giant: 1 },
  twinAim: { ...BASE, mode: 1, layers: 2, layerSpeed: 0.7, script: 3 },
  zigzagAim: { ...BASE, mode: 1, weave: 2, weaveTurn: 70, weavePeriod: 0.35 },
  accelRing: { ...BASE, mode: 0, speed0: 0.35, accel: 0.8, maxMul: 2.2 },
  homingRing: { ...BASE, mode: 0, turn: 40 },
  sweepLaser: { ...BASE, mode: 1, beam: 1, beamSweep: 90, beamTime: 1.2 },
  bounceRing: { ...BASE, mode: 0, bounces: 2 },
  freezeRing: { ...BASE, mode: 0, script: 1 },
  shatterRing: { ...BASE, mode: 0, script: 2 },
  pulseRing: { ...BASE, mode: 2, fan: -1, scatter: 340, script: 3 },
  freezeCurtain: { ...BASE, mode: 2, fan: -1, lineWidth: 300, script: 1 },
  splitCurtain: { ...BASE, mode: 2, fan: -1, lineWidth: 300, script: 2 },
  wavyRing: { ...BASE, mode: 0, waveAmp: 0.35, waveFreq: 3 },
  petalFan: { ...BASE, mode: 1, waveAmp: 0.4, waveFreq: 3 },
  waveSpiral: { ...BASE, mode: 0, waveAmp: 0.3, waveFreq: 1.7, wavePhase: 0.8 },
  tide: { ...BASE, mode: 2, waveAmp: 0.5, waveFreq: 2, wavePhase: 1.3 },
  ladder: { ...BASE, mode: 2, fan: -1, altSpeed: 0.6, lineWidth: 300 },
  helix: { ...BASE, mode: 0, layers: 2, layerFlip: 1 },
  rapidFan: { ...BASE, mode: 1, speedStep: 0.12, speedCycle: 3 },
  lightRain: { ...BASE, mode: 2, fan: -1, speed0: 1.2, scatter: 340, jitter: 3 },
  swirl: { ...BASE, mode: 0, curve: 30, curveTime: 8, curveSame: 1 },
  mine: { ...BASE, mode: 1, mine: 1, travel: 0.9, fuse: 2.6 },
  meteor: { ...BASE, mode: 0, fuse: 1.1, meteor: 1, blastRadius: 34, meteorGap: 70 },
  gridLaser: { ...BASE, mode: 0, grid: 1, gridGap: 72 },
  gravity: { ...BASE, mode: 3, gravity: 180 },
  orbit: { ...BASE, mode: 0, curveTime: 2, orbitRadius: 40 },
  snake: { ...BASE, mode: 1, fan: -1, turn: 70, trail: 11 },
  bubble: { ...BASE, mode: 1, speed0: 0.5, radius: 2, grow: 10, growMax: 26 },
};

/** チャージビームの印(弾の script)。アプリの Bullet.beamScript と同じ */
export const BEAM_SCRIPT = 4;
/** ブーメランと巨大弾の印。アプリの Bullet.boomerangScript / giantScript と同じ */
export const BOOMERANG_SCRIPT = 5, GIANT_SCRIPT = 6;
/** 地雷と爆風(隕石・地雷の爆発)の印。アプリの Bullet.mineScript / blastScript と同じ */
export const MINE_SCRIPT = 7, BLAST_SCRIPT = 8;
/** 蛇行(なめらか)とジグザグ(カクッと)の印。アプリの Bullet.weaveScript / zigzagScript と同じ */
export const WEAVE_SCRIPT = 9, ZIGZAG_SCRIPT = 10;

/** 弾を1つ出す関数(呼ぶ側の Bullet の形に合わせる) */
export interface BulletExtra { turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number; gravity: number; radius: number; grow: number; growMax: number; fuse: number }
const NONE: BulletExtra = { turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, gravity: 0, radius: 0, grow: 0, growMax: 0, fuse: 0 };
export type AddBullet = (x: number, y: number, vx: number, vy: number, extra: BulletExtra) => void;

export function emitRecipe(r: Recipe, m: { c: number; r: number; k: number }, k: number, cx: number, cy: number, px: number, py: number,
  off: number, sp: number, n: number, rng: () => number, homingSeconds: number, add: AddBullet): void {
  const deg = Math.PI / 180;
  const fanDeg = r.fan < 0 ? 0 : (r.fan > 0 ? r.fan : m.r);
  let layerSpeed = 1;
  for (let layer = 0; layer < Math.max(1, r.layers); layer++) {
    const layerShift = layer * r.layerAngle * deg;
    let base: number;
    if (r.mode === 0) base = (r.layerFlip !== 0 && layer % 2 === 1 ? -1 : 1) * k * m.r * deg * r.spin + off;
    else if (r.mode === 1) base = Math.atan2(py - cy, px - cx) + off;
    else if (r.mode === 3) base = -Math.PI / 2 + off;
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
      if (r.speedJitter !== 0) f *= 1 + (rng() - 0.5) * 2 * r.speedJitter;
      let x = cx;
      if (r.lineWidth !== 0) x += (n > 1 ? j / (n - 1) - 0.5 : 0) * r.lineWidth;
      if (r.scatter !== 0) x += (rng() - 0.5) * r.scatter;
      const side = j % 2 === 0 ? 1 : -1;
      if (r.meteor !== 0) {
        // 隕石: 自機のいる場所(2つ目からは、そのまわり)に、予告の円を出してから衝撃を落とす。アプリの Bullet.blast と同じ
        const mx = j === 0 ? px : px + Math.cos(a) * r.meteorGap, my = j === 0 ? py : py + Math.sin(a) * r.meteorGap;
        add(mx, my, 0, 0, { ...NONE, bounces: 1, script: BLAST_SCRIPT, radius: r.blastRadius, fuse: r.fuse });
        continue;
      }
      if (r.grid !== 0) {
        // 格子レーザー: 自機を通る縦と横の線から、間をあけて交互に。画面の端から反対の端まで
        const idx = Math.trunc(j / 2);
        const gap = idx === 0 ? 0 : (idx % 2 === 1 ? 1 : -1) * Math.trunc((idx + 1) / 2) * r.gridGap;
        if (j % 2 === 0) add(px + gap, -10, Math.cos(Math.PI / 2), Math.sin(Math.PI / 2), { ...NONE, bounces: 1, script: BEAM_SCRIPT });
        else add(-10, py + gap, Math.cos(0), Math.sin(0), { ...NONE, bounces: 1, script: BEAM_SCRIPT });
        continue;
      }
      if (r.beam !== 0) {
        // チャージビーム: その場に止まったまま、向き(長さ1)だけを持つ。アプリの Bullet.beam と同じ
        if (r.beamSweep !== 0) {
          const a0 = a - side * r.beamSweep * deg / 2;
          add(x, cy, Math.cos(a0), Math.sin(a0), { ...NONE, turn: side * r.beamSweep * deg / r.beamTime, homeLeft: r.beamTime, bounces: 1, script: BEAM_SCRIPT });
        } else {
          add(x, cy, Math.cos(a), Math.sin(a), { ...NONE, bounces: 1, script: BEAM_SCRIPT });
        }
        continue;
      }
      if (r.orbitRadius !== 0) {
        // 衛星: 発射口のまわりの円の上から、円に沿う向きに出て、curveTime 秒だけ回ってから飛び出す
        const speed = sp * f;
        add(cx + Math.cos(a) * r.orbitRadius, cy + Math.sin(a) * r.orbitRadius, Math.cos(a + Math.PI / 2) * speed, Math.sin(a + Math.PI / 2) * speed,
          { ...NONE, turn: speed / r.orbitRadius, homeLeft: r.curveTime, script: BOOMERANG_SCRIPT });
        continue;
      }
      if (r.curve !== 0) {
        // ブーメラン: 決まった時間だけ向きを回す(追尾ではない)
        add(x, cy, Math.cos(a) * sp * f, Math.sin(a) * sp * f, { ...NONE, turn: (r.curveSame !== 0 ? 1 : side) * r.curve * deg, homeLeft: r.curveTime, bounces: r.bounces, script: BOOMERANG_SCRIPT });
        continue;
      }
      if (r.weave !== 0) {
        // 蛇行(なめらか)・ジグザグ(カクッと): 向きを左右に切り替えながら進む。アプリと同じ
        const smooth = r.weave === 1;
        const swing = smooth ? r.weaveTurn * deg * r.weavePeriod / 4 : r.weaveTurn * deg / 2;
        const a0 = a - side * swing;
        add(x, cy, Math.cos(a0) * sp * f, Math.sin(a0) * sp * f, { ...NONE, turn: side * r.weaveTurn * deg, homeLeft: smooth ? r.weavePeriod / 2 : r.weavePeriod,
          bounces: r.bounces, script: smooth ? WEAVE_SCRIPT : ZIGZAG_SCRIPT, fuse: r.weavePeriod });
        continue;
      }
      // スネーク: 後ろの弾ほど、進む向きの後ろから出る(同じように曲がるので、列になって追いかける)
      const bx = x - Math.cos(a) * r.trail * j, by = cy - Math.sin(a) * r.trail * j;
      add(bx, by, Math.cos(a) * sp * f, Math.sin(a) * sp * f, {
        turn: r.turn * deg, homeLeft: r.mine !== 0 ? r.travel : r.turn > 0 ? homingSeconds : 0, accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces,
        script: r.mine !== 0 ? MINE_SCRIPT : r.giant !== 0 ? GIANT_SCRIPT : r.script,
        gravity: r.gravity, radius: r.radius, grow: r.grow, growMax: r.growMax, fuse: r.mine !== 0 ? r.fuse : 0,
      });
    }
    layerSpeed *= r.layerSpeed;
  }
}
