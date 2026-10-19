import { describe, expect, it } from "vitest";
import { containsNgWord } from "../src/ngwords/index.js";
import { ID_ALPHABET, isValidShortId, newShortId, normalizeShortId } from "../src/shortId.js";
import { validateComment, validatePublish } from "../src/validate.js";
import { ogpSvg, renderOgp, OGP_HEIGHT, OGP_WIDTH } from "../src/ogp.js";
import { snapshot } from "../src/sim.js";
import { pickLang, renderSharePage } from "../src/share.js";

const em = (o: object = {}) => ({ t: "ring", x: 0.5, y: 0.2, s: 0, e: 20, i: 1, c: 16, v: 2, r: 6, k: 0, ph: 0, ...o });
const good = (o: object = {}) => ({
  name: "はじめての渦", authorName: "Koshin", mode: "survive", durationSec: 20, emitters: [em()], clearReplay: "AQIDBAUGBwg=", ...o,
});

describe("validatePublish", () => {
  it("正しい入力を通し、小数を2桁に揃える", () => {
    const r = validatePublish(good({ emitters: [em({ x: 0.333333, v: 1.999 })] }));
    expect(r.ok).toBe(true);
    if (r.ok) { expect(r.stage.emitters[0]!.x).toBe(0.33); expect(r.stage.emitters[0]!.v).toBe(2); }
  });
  it.each([
    ["名前が空", { name: "  " }, "name-length"],
    ["名前が21文字", { name: "あ".repeat(21) }, "name-length"],
    ["作者名が13文字", { authorName: "a".repeat(13) }, "author-length"],
    ["モード不正", { mode: "hard" }, "mode"],
    ["時間が選択肢外", { durationSec: 25 }, "duration"],
    ["発射台なし", { emitters: [] }, "emitter-count"],
    ["発射台9個", { emitters: Array.from({ length: 9 }, () => em()) }, "emitter-count"],
    ["パターン不正", { emitters: [em({ t: "laser" })] }, "emitter-pattern"],
    ["弾数37", { emitters: [em({ c: 37 })] }, "emitter-range"],
    ["弾数が小数", { emitters: [em({ c: 3.5 })] }, "emitter-range"],
    ["速さ0.5", { emitters: [em({ v: 0.5 })] }, "emitter-range"],
    ["間隔0.01", { emitters: [em({ i: 0.01 })] }, "emitter-range"],
    ["NaN", { emitters: [em({ x: Number.NaN })] }, "emitter-range"],
    ["開始が時間以降", { emitters: [em({ s: 20 })] }, "emitter-timing"],
    ["終了が開始以前", { emitters: [em({ s: 5, e: 5 })] }, "emitter-timing"],
    ["リプレイなし", { clearReplay: undefined }, "replay"],
    ["リプレイが不正文字", { clearReplay: "!!!!!!!!!!" }, "replay"],
    ["名前にNGワード", { name: "死ね" }, "name-ng-word"],
    ["作者名にNGワード", { authorName: "fuck" }, "author-ng-word"],
  ])("%s は拒否", (_n, patch, error) => {
    const r = validatePublish(good(patch));
    expect(r).toEqual({ ok: false, error });
  });
  it("ボス: HP は 100〜1000 の 50 刻み", () => {
    const boss = { mode: "boss", durationSec: 60, bossMove: 1 };
    expect(validatePublish(good({ ...boss, bossHp: 400 })).ok).toBe(true);
    expect(validatePublish(good({ ...boss, bossHp: 420 }))).toEqual({ ok: false, error: "boss-hp" });
    expect(validatePublish(good({ ...boss, bossHp: 50 }))).toEqual({ ok: false, error: "boss-hp" });
    expect(validatePublish(good({ ...boss, bossHp: 400, bossMove: 3 }))).toEqual({ ok: false, error: "boss-move" });
  });
  it("オブジェクト以外は拒否", () => {
    expect(validatePublish(null)).toEqual({ ok: false, error: "invalid-data" });
    expect(validatePublish("x")).toEqual({ ok: false, error: "invalid-data" });
  });
});

describe("NGワード", () => {
  it.each(["死ね", "シネ", "し ね", "ＦＵＣＫ", "f u c k", "fvck".replace("v", "u"), "h1tler", "http://example.com", "line:abc", "まんこ"])("%s を検出", (w) => {
    expect(containsNgWord(w)).toBe(true);
  });
  it.each(["はじめての渦", "Classic Pass", "Assassin Dash", "Scunthorpe", "地獄の花火大会", "Spiral 3", "ボスを倒せ"])("%s は通す", (w) => {
    expect(containsNgWord(w)).toBe(false);
  });
});

describe("短縮ID", () => {
  it("紛らわしい文字を含まない", () => {
    for (const c of "01OIL") expect(ID_ALPHABET).not.toContain(c);
    expect(ID_ALPHABET.length).toBe(31);
  });
  it("5文字で、使える文字だけ", () => {
    for (let i = 0; i < 500; i++) { const id = newShortId(); expect(id).toHaveLength(5); expect(isValidShortId(id)).toBe(true); }
  });
  it("検証と正規化", () => {
    expect(isValidShortId("K7X2P")).toBe(true);
    expect(isValidShortId("K7X2")).toBe(false);
    expect(isValidShortId("K7X20")).toBe(false);
    expect(normalizeShortId(" k7x2p ")).toBe("K7X2P");
  });
});

describe("OGP 画像", () => {
  const stage = (validatePublish(good({ name: "地獄の渦 Inferno" })) as { ok: true; stage: never }).stage;
  it("SVG に発射台と弾が入る", () => {
    const svg = ogpSvg(stage, "K7X2P");
    expect(svg).toContain("K7X2P");
    expect(svg).toContain("<circle");
  });
  it("弾の位置を返す", () => {
    expect(snapshot(stage).bullets.length).toBeGreaterThan(10);
  });
  it("PNG は 1200×630", () => {
    const png = renderOgp(stage, "K7X2P");
    expect(png.subarray(1, 4).toString()).toBe("PNG");
    expect(png.readUInt32BE(16)).toBe(OGP_WIDTH);
    expect(png.readUInt32BE(20)).toBe(OGP_HEIGHT);
  });
  it("ボス戦もPNGにできる", () => {
    const b = (validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1 })) as { ok: true; stage: never }).stage;
    expect(renderOgp(b, "ABCDE").length).toBeGreaterThan(1000);
  });
});

describe("共有ページ", () => {
  const stage = { name: "<b>渦</b>", authorName: "A&B", mode: "survive" as const, durationSec: 20, bossHp: null, plays: 10, clears: 4, likes: 2 };
  it("OGP タグと、HTML エスケープ", () => {
    const { status, html } = renderSharePage({ id: "K7X2P", stage, lang: "ja", origin: "https://ex.test", appStoreUrl: "https://apps.apple.com/x" });
    expect(status).toBe(200);
    for (const tag of ['property="og:title"', 'property="og:description"', 'property="og:image" content="https://ex.test/og/K7X2P.png"', 'name="twitter:card" content="summary_large_image"']) expect(html).toContain(tag);
    expect(html).not.toContain("<b>渦</b>");
    expect(html).toContain("&lt;b&gt;渦&lt;/b&gt;");
    expect(html).toContain("40%");
    expect(html).toContain('<html lang="ja">');
  });
  it("英語", () => {
    const { html } = renderSharePage({ id: "K7X2P", stage, lang: "en", origin: "https://ex.test", appStoreUrl: "u" });
    expect(html).toContain('<html lang="en">');
    expect(html).toContain("Clear rate");
  });
  it("存在しないステージは 404", () => {
    const { status, html } = renderSharePage({ id: "ZZZZZ", stage: null, lang: "ja", origin: "https://ex.test", appStoreUrl: "u" });
    expect(status).toBe(404);
    expect(html).toContain("見つかりません");
    expect(html).toContain("noindex");
  });
  it("言語の選択", () => {
    expect(pickLang("ja-JP,ja;q=0.9,en;q=0.8")).toBe("ja");
    expect(pickLang("en-US,en;q=0.9")).toBe("en");
    expect(pickLang("fr")).toBe("en");
    expect(pickLang(undefined)).toBe("en");
    expect(pickLang("en", "ja")).toBe("ja");
  });
});


describe("validatePublish: ダメージ勝負・ライフ・新しいパターン", () => {
  it("ダメージ勝負は HP なし・ボスの動きあり", () => {
    const r = validatePublish(good({ mode: "damage", durationSec: 60, bossMove: 2 }));
    expect(r.ok).toBe(true);
    if (r.ok) { expect(r.stage.bossHp).toBeNull(); expect(r.stage.bossMove).toBe(2); }
    expect(validatePublish(good({ mode: "damage", durationSec: 20, bossMove: 0 }))).toEqual({ ok: false, error: "duration" });
    expect(validatePublish(good({ mode: "damage", durationSec: 60 }))).toEqual({ ok: false, error: "boss-move" });
  });
  it("ライフ制・HP制を受け付け、標準(ライフ1)は保存しない", () => {
    const hp = validatePublish(good({ lifeMode: "hp", lifeCount: 10 }));
    expect(hp.ok && hp.stage.lifeMode).toBe("hp");
    expect(hp.ok && hp.stage.lifeCount).toBe(10);
    const lives = validatePublish(good({ lifeMode: "lives", lifeCount: 3 }));
    expect(lives.ok && lives.stage.lifeCount).toBe(3);
    const std = validatePublish(good({ lifeMode: "lives", lifeCount: 1 }));
    expect(std.ok && std.stage.lifeMode).toBeUndefined();
    const none = validatePublish(good());
    expect(none.ok && "lifeMode" in none.stage).toBe(false);
  });
  it.each([
    ["ライフが6", { lifeMode: "lives", lifeCount: 6 }, "life-count"],
    ["HPが2", { lifeMode: "hp", lifeCount: 2 }, "life-count"],
    ["HPが21", { lifeMode: "hp", lifeCount: 21 }, "life-count"],
    ["方式が不正", { lifeMode: "god", lifeCount: 3 }, "life-mode"],
    ["方式なしで数だけ", { lifeCount: 3 }, "life-count"],
    ["小数", { lifeMode: "lives", lifeCount: 2.5 }, "life-count"],
  ])("%s は拒否", (_n, over, err) => {
    expect(validatePublish(good(over))).toEqual({ ok: false, error: err });
  });
  it.each(["sideL", "sideR", "corner"])("新しいパターン %s を受け付ける", (t) => {
    expect(validatePublish(good({ emitters: [em({ t })] })).ok).toBe(true);
  });
  it("OGP 画像の生成も新しいモード・パターンで動く", () => {
    const r = validatePublish(good({ mode: "damage", durationSec: 60, bossMove: 1, emitters: [em({ t: "corner" }), em({ t: "sideL" })] }));
    if (!r.ok) throw new Error("invalid");
    expect(ogpSvg(r.stage, "ABCDE")).toContain("<svg");
  });
});


describe("validateComment", () => {
  it("空白をそろえて通す", () => {
    expect(validateComment("  むずい\n\nけど  好き ")).toEqual({ ok: true, text: "むずい けど 好き" });
    expect(validateComment("あ".repeat(80)).ok).toBe(true);
  });
  it.each([
    ["空", "", "comment-length"],
    ["空白だけ", "  \n ", "comment-length"],
    ["81文字", "あ".repeat(81), "comment-length"],
    ["数字ではない", 123, "comment-length"],
    ["NGワード", "しね", "comment-ng-word"],
    ["URL(https)", "見て https://a.example/x", "comment-link"],
    ["URL(www)", "www.example.com", "comment-link"],
    ["ドメイン", "example.com へどうぞ", "comment-link"],
    ["//", "a//b", "comment-link"],
  ])("%s は拒否", (_n, text, err) => {
    expect(validateComment(text)).toEqual({ ok: false, error: err });
  });
  it("ふつうの文や顔文字は通る", () => {
    expect(validateComment("やっと倒せた！！(^o^) 3.5秒はやい").ok).toBe(true);
  });
});


describe("validatePublish: 出す場所(p)", () => {
  it("ボス戦では好きな場所を指定でき、標準(0)は保存しない", () => {
    const r = validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1, emitters: [em({ p: 1, x: 0.2, y: 0.5 }), em({ p: 0 }), em()] }));
    expect(r.ok).toBe(true);
    if (r.ok) { expect(r.stage.emitters[0]!.p).toBe(1); expect("p" in r.stage.emitters[1]!).toBe(false); expect("p" in r.stage.emitters[2]!).toBe(false); }
  });
  it("生き残りでは指定できない・範囲外は拒否", () => {
    expect(validatePublish(good({ emitters: [em({ p: 1 })] }))).toEqual({ ok: false, error: "emitter-point" });
    expect(validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1, emitters: [em({ p: 2 })] }))).toEqual({ ok: false, error: "emitter-range" });
  });
  it("時間無制限(0)はボス戦だけ", () => {
    expect(validatePublish(good({ mode: "boss", durationSec: 0, bossHp: 400, bossMove: 1 })).ok).toBe(true);
    expect(validatePublish(good({ mode: "survive", durationSec: 0 }))).toEqual({ ok: false, error: "duration" });
    expect(validatePublish(good({ mode: "damage", durationSec: 0, bossMove: 0 }))).toEqual({ ok: false, error: "duration" });
  });
  it("追尾弾を受け付ける", () => {
    expect(validatePublish(good({ emitters: [em({ t: "homing" })] })).ok).toBe(true);
  });
});
