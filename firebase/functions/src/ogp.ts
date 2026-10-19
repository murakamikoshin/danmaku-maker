import { Resvg } from "@resvg/resvg-js";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { snapshot, H, W } from "./sim.js";
import { PALETTE, THEME_PALETTES } from "./palette.js";
import type { Stage } from "./validate.js";

export const OGP_WIDTH = 1200;
export const OGP_HEIGHT = 630;

const FONT_PATH = fileURLToPath(new URL("../assets/NotoSansJP-Bold.ttf", import.meta.url));

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** 長い名前を2行に折り返す（全角は幅2として数える） */
function wrap(text: string, maxWidth: number): string[] {
  const lines: string[] = [];
  let cur = "", w = 0;
  for (const ch of text) {
    const cw = ch.codePointAt(0)! < 0x1100 ? 1 : 2;
    if (w + cw > maxWidth && cur) { lines.push(cur); cur = ""; w = 0; }
    cur += ch; w += cw;
  }
  if (cur) lines.push(cur);
  return lines.slice(0, 2);
}

export function ogpSvg(stage: Stage, shortId: string): string {
  const { bullets } = snapshot(stage);
  const colors = THEME_PALETTES[stage.themeBullets ?? ""]?.bullets ?? PALETTE;
  const bgColor = THEME_PALETTES[stage.themeBackground ?? ""]?.background ?? "#0a0818";
  const scale = 1.1;
  const fx = 760, fy = (OGP_HEIGHT - H * scale) / 2;
  const firstWave = stage.mode === "sequence" ? stage.waves?.[0] : undefined;
  const boss = firstWave ? firstWave.kind === "boss" : stage.mode !== "survive";
  const emittersList = firstWave ? firstWave.emitters : stage.emitters;
  const dots = bullets.map((b) => `<circle cx="${(b.x * scale).toFixed(1)}" cy="${(b.y * scale).toFixed(1)}" r="6.6" fill="${colors[b.k]}"/>`).join("");
  const cores = bullets.map((b) => `<circle cx="${(b.x * scale).toFixed(1)}" cy="${(b.y * scale).toFixed(1)}" r="3.3" fill="#fff"/>`).join("");
  const markers = boss
    ? `<polygon points="${Array.from({ length: 12 }, (_, i) => { const a = (i * Math.PI) / 6, r = i % 2 ? 14 : 22; return `${((W / 2 + Math.cos(a) * r) * scale).toFixed(1)},${((H * 0.18 + Math.sin(a) * r) * scale).toFixed(1)}`; }).join(" ")}" fill="#ff6b9d"/>`
    : emittersList.filter((m) => !["rain", "sideL", "sideR", "corner"].includes(m.t)).map((m) => {
        const x = m.x * W * scale, y = m.y * H * scale, d = 8 * scale;
        return `<polygon points="${x},${y - d} ${x + d},${y} ${x},${y + d} ${x - d},${y}" fill="none" stroke="${colors[m.k]}" stroke-width="2"/>`;
      }).join("");
  const title = wrap(stage.name, 22);
  const titleSvg = title.map((l, i) => `<text x="70" y="${250 + i * 78}" font-size="64" font-weight="700" fill="#efeaff">${esc(l)}</text>`).join("");
  const badge = stage.mode === "sequence" ? "WAVES" : boss ? "BOSS" : "SURVIVE";
  const badgeColor = boss ? "#ff6b9d" : "#5ce1e6";
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${OGP_WIDTH}" height="${OGP_HEIGHT}" viewBox="0 0 ${OGP_WIDTH} ${OGP_HEIGHT}" font-family="Noto Sans JP">
<defs><linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#1c1740"/><stop offset="1" stop-color="#0a0818"/></linearGradient>
<clipPath id="f"><rect x="0" y="0" width="${W * scale}" height="${H * scale}" rx="14"/></clipPath></defs>
<rect width="${OGP_WIDTH}" height="${OGP_HEIGHT}" fill="url(#bg)"/>
<text x="70" y="96" font-size="30" font-weight="700" fill="#ff6b9d">DANMAKU MAKER</text>
<rect x="70" y="130" width="${badge.length * 22 + 36}" height="44" rx="22" fill="none" stroke="${badgeColor}" stroke-width="3"/>
<text x="88" y="162" font-size="26" font-weight="700" fill="${badgeColor}">${badge}</text>
${titleSvg}
<text x="70" y="${250 + title.length * 78 + 10}" font-size="34" fill="#a39bd0">by ${esc(stage.authorName)}</text>
<text x="70" y="560" font-size="46" font-weight="700" fill="#ffd166">ID ${esc(shortId)}</text>
<g transform="translate(${fx},${fy})"><rect width="${W * scale}" height="${H * scale}" rx="14" fill="${bgColor}" stroke="#332b62" stroke-width="3"/>
<g clip-path="url(#f)">${markers}${dots}${cores}
<polygon points="${(W / 2) * scale},${(H * 0.85 - 11) * scale} ${(W / 2 + 8) * scale},${(H * 0.85 + 8) * scale} ${(W / 2) * scale},${(H * 0.85 + 4) * scale} ${(W / 2 - 8) * scale},${(H * 0.85 + 8) * scale}" fill="#5ce1e6"/></g></g>
</svg>`;
}

export function renderOgp(stage: Stage, shortId: string): Buffer {
  const fontFiles = existsSync(FONT_PATH) ? [FONT_PATH] : [];
  const resvg = new Resvg(ogpSvg(stage, shortId), {
    fitTo: { mode: "width", value: OGP_WIDTH },
    font: { fontFiles, loadSystemFonts: fontFiles.length === 0, defaultFontFamily: "Noto Sans JP" },
  });
  return resvg.render().asPng();
}
