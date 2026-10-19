import type { Mode } from "./validate.js";

export type Lang = "ja" | "en";

export interface SharedStage {
  name: string; authorName: string; mode: Mode; durationSec: number;
  bossHp: number | null; plays: number; clears: number; likes: number;
}

export function pickLang(acceptLanguage: string | undefined, override?: string): Lang {
  if (override === "ja" || override === "en") return override;
  const first = (acceptLanguage ?? "").split(",")[0]?.trim().toLowerCase() ?? "";
  return first.startsWith("ja") ? "ja" : "en";
}

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

const T = {
  ja: {
    app: "弾幕メーカー",
    survive: (s: number) => `${s}秒耐える`,
    boss: (hp: number, s: number) => (s === 0 ? `ボス戦 HP${hp}・時間無制限` : `ボス戦 HP${hp}・制限${s}秒`),
    damage: (s: number) => `ダメージ勝負 ${s}秒`,
    desc: (a: string, mode: string, rate: string, plays: number) => `${a} さんが作った弾幕ステージ。${mode}・クリア率${rate}・挑戦${plays}回。クリアできる？`,
    by: "作者", plays: "挑戦", clears: "クリア", rate: "クリア率", likes: "いいね",
    open: "アプリで遊ぶ", store: "App Store でダウンロード",
    tagline: "弾幕ステージを作って、投稿して、世界中で遊ぼう。",
    notFoundTitle: "ステージが見つかりません", notFoundBody: "URL が間違っているか、ステージが非公開になった可能性があります。",
    top: "弾幕メーカーについて",
  },
  en: {
    app: "Danmaku Maker",
    survive: (s: number) => `Survive ${s} s`,
    boss: (hp: number, s: number) => (s === 0 ? `Boss fight · HP ${hp} · no time limit` : `Boss fight · HP ${hp} · ${s} s limit`),
    damage: (s: number) => `Damage race · ${s} s`,
    desc: (a: string, mode: string, rate: string, plays: number) => `A bullet-hell stage by ${a}. ${mode} · ${rate} clear rate · ${plays} plays. Can you clear it?`,
    by: "By", plays: "Plays", clears: "Clears", rate: "Clear rate", likes: "Likes",
    open: "Play in the app", store: "Download on the App Store",
    tagline: "Build bullet-hell stages, share them, and dodge the world.",
    notFoundTitle: "Stage not found", notFoundBody: "The link may be wrong, or the stage is no longer public.",
    top: "About Danmaku Maker",
  },
} as const;

const CSS = `:root{color-scheme:dark;--ink:#110e26;--panel:#1c1740;--line:#332b62;--fg:#efeaff;--dim:#a39bd0;--pink:#ff6b9d;--gold:#ffd166}
*{box-sizing:border-box}body{margin:0;background:var(--ink);color:var(--fg);font-family:"Hiragino Sans","Noto Sans JP",system-ui,sans-serif;line-height:1.6}
main{max-width:560px;margin:0 auto;padding:28px 16px 48px;display:flex;flex-direction:column;gap:18px}
.brand{color:var(--pink);font-weight:700;letter-spacing:.06em}h1{font-size:28px;line-height:1.25;margin:0;overflow-wrap:anywhere}
.card{background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:16px;display:grid;grid-template-columns:repeat(2,1fr);gap:10px}
.card div span{display:block;font-size:12px;color:var(--dim)}.card div b{font-size:20px;color:var(--gold)}
.badge{display:inline-block;font-size:12px;padding:1px 9px;border-radius:99px;border:1px solid currentColor;color:#5ce1e6;margin-right:8px}.badge.boss{color:var(--pink)}
.btn{display:block;text-align:center;padding:14px;border-radius:12px;font-weight:700;text-decoration:none}
.btn.primary{background:var(--pink);color:#1a0b14}.btn.sub{border:1px solid var(--line);color:var(--fg)}
p{margin:0;color:var(--dim)}`;

function shell(lang: Lang, head: string, body: string): string {
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${head}<style>${CSS}</style></head><body><main>${body}</main></body></html>`;
}

export interface PageInput {
  id: string; stage: SharedStage | null; lang: Lang; origin: string; appStoreUrl: string;
}

export function renderSharePage(i: PageInput): { status: number; html: string } {
  const t = T[i.lang];
  if (!i.stage) {
    return {
      status: 404,
      html: shell(i.lang,
        `<title>${esc(t.notFoundTitle)} | ${t.app}</title><meta name="robots" content="noindex">`,
        `<div class="brand">${t.app}</div><h1>${esc(t.notFoundTitle)}</h1><p>${esc(t.notFoundBody)}</p><a class="btn primary" href="${esc(i.appStoreUrl)}">${esc(t.store)}</a>`),
    };
  }
  const s = i.stage;
  const rate = s.plays > 0 ? `${Math.round((s.clears / s.plays) * 100)}%` : "—";
  const modeText = s.mode === "boss" ? t.boss(s.bossHp ?? 0, s.durationSec) : s.mode === "damage" ? t.damage(s.durationSec) : t.survive(s.durationSec);
  const url = `${i.origin}/s/${i.id}`;
  const title = `${s.name} | ${t.app}`;
  const desc = t.desc(s.authorName, modeText, rate, s.plays);
  const head = `<title>${esc(title)}</title>
<meta name="description" content="${esc(desc)}">
<meta property="og:type" content="website"><meta property="og:site_name" content="${t.app}">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(desc)}">
<meta property="og:url" content="${esc(url)}"><meta property="og:image" content="${esc(`${i.origin}/og/${i.id}.png`)}">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(desc)}"><meta name="twitter:image" content="${esc(`${i.origin}/og/${i.id}.png`)}">
<link rel="canonical" href="${esc(url)}">`;
  const body = `<div class="brand">${t.app}</div>
<div><span class="badge ${s.mode === "survive" ? "" : "boss"}">${s.mode === "boss" ? "BOSS" : s.mode === "damage" ? "DAMAGE" : "SURVIVE"}</span>${esc(modeText)}</div>
<h1>${esc(s.name)}</h1><p>${t.by}: ${esc(s.authorName)}</p>
<section class="card"><div><span>${t.rate}</span><b>${rate}</b></div><div><span>${t.likes}</span><b>${s.likes}</b></div><div><span>${t.plays}</span><b>${s.plays}</b></div><div><span>${t.clears}</span><b>${s.clears}</b></div></section>
<a class="btn primary" href="${esc(i.appStoreUrl)}">${esc(t.store)}</a>
<p>${esc(t.tagline)}</p>`;
  return { status: 200, html: shell(i.lang, head, body) };
}
