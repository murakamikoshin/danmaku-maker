import { describe, expect, it } from "vitest";
import { beamHits, blastHits } from "../src/fullsim.js";
import { crossedMilestone, pushLang, pushText } from "../src/notify.js";
import { containsNgWord } from "../src/ngwords/index.js";
import { ID_ALPHABET, isValidShortId, newShortId, normalizeShortId } from "../src/shortId.js";
import { validateComment, validateDisplayName, validatePublish } from "../src/validate.js";
import { afterGrant, afterPost, checkPost, FREE_DAILY_POSTS, HARD_DAILY_POSTS, jstDay, MAX_EXTRA_TICKETS, readQuota } from "../src/quota.js";
import { pathPosition, validatePath } from "../src/custompath.js";
import { nameKeys, normalizeName, queryGram } from "../src/search.js";
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
  it("URLを知っている人だけの投稿(unlisted)は、クリア記録がなくても通る", () => {
    const r = validatePublish(good({ clearReplay: undefined, unlisted: true }));
    expect(r.ok).toBe(true);
    if (r.ok) expect(r.clearReplay).toBeNull();
  });
  it("unlisted でなければ、クリア記録なしは拒否のまま", () => {
    expect(validatePublish(good({ clearReplay: undefined, unlisted: false }))).toEqual({ ok: false, error: "replay" });
  });
  it("ボス: HP は 100〜1000 の 50 刻み", () => {
    const boss = { mode: "boss", durationSec: 60, bossMove: 1 };
    expect(validatePublish(good({ ...boss, bossHp: 400 })).ok).toBe(true);
    expect(validatePublish(good({ ...boss, bossHp: 420 }))).toEqual({ ok: false, error: "boss-hp" });
    expect(validatePublish(good({ ...boss, bossHp: 50 }))).toEqual({ ok: false, error: "boss-hp" });
    // ボスの動きは 0〜6(止まる・横2種類・上下・円・8の字・ワープ)。7 以上・負・小数・文字は拒否
    for (const mv of [3, 4, 5, 6, 7, 8, 9, 10]) expect(validatePublish(good({ ...boss, bossHp: 400, bossMove: mv })).ok).toBe(true);
    for (const bad of [11, 12, -1, 1.5, "2"]) expect(validatePublish(good({ ...boss, bossHp: 400, bossMove: bad }))).toEqual({ ok: false, error: "boss-move" });
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


describe("validatePublish: BGM", () => {
  it("選んだ曲を保存し、モードごとの標準と同じ指定は保存しない", () => {
    const r = validatePublish(good({ bgm: 3 }));
    expect(r.ok && r.stage.bgm).toBe(3);
    const std = validatePublish(good({ bgm: 0 }));
    expect(std.ok && "bgm" in std.stage).toBe(false);
    const boss = validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1, bgm: 1 }));
    expect(boss.ok && "bgm" in boss.stage).toBe(false);
    const boss0 = validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1, bgm: 0 }));
    expect(boss0.ok && boss0.stage.bgm).toBe(0);
    expect(validatePublish(good()).ok && "bgm" in (validatePublish(good()) as { stage: object }).stage).toBe(false);
  });
  it.each([[5], [-1], [1.5], ["a"]])("範囲外 %s は拒否", (b) => {
    expect(validatePublish(good({ bgm: b }))).toEqual({ ok: false, error: "bgm" });
  });
});


describe("validatePublish: 見た目と発射位置の予告", () => {
  it("ステージの見た目を保存し、標準(classic)は保存しない", () => {
    const r = validatePublish(good({ themeBullets: "sakura", themeBackground: "ocean", themeShip: "classic" }));
    expect(r.ok && r.stage.themeBullets).toBe("sakura");
    expect(r.ok && r.stage.themeBackground).toBe("ocean");
    expect(r.ok && "themeShip" in r.stage).toBe(false);
    const rw = validatePublish(good({ themeBullets: "gold", themeBackground: "neon", themeShip: "rainbow" }));
    expect(rw.ok && rw.stage.themeBullets).toBe("gold");
    expect(rw.ok && rw.stage.themeShip).toBe("rainbow");
    expect(validatePublish(good({ themeBullets: "galaxy" }))).toEqual({ ok: false, error: "theme" });
    expect(validatePublish(good({ themeShip: 3 }))).toEqual({ ok: false, error: "theme" });
  });
  it("予告を出さない設定は、生き残りだけで、trueだけ保存する", () => {
    const r = validatePublish(good({ hideMarkers: true }));
    expect(r.ok && r.stage.hideMarkers).toBe(true);
    const f = validatePublish(good({ hideMarkers: false }));
    expect(f.ok && "hideMarkers" in f.stage).toBe(false);
    expect(validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 0, hideMarkers: true }))).toEqual({ ok: false, error: "markers" });
    expect(validatePublish(good({ hideMarkers: "yes" }))).toEqual({ ok: false, error: "markers" });
  });
  it("OGP 画像が、ステージの見た目の色で描かれる", () => {
    const r = validatePublish(good({ themeBullets: "sakura", themeBackground: "aurora" }));
    if (!r.ok) throw new Error("invalid");
    const svg = ogpSvg(r.stage, "ABCDE");
    expect(svg).toContain("#07120f");
    expect(svg).not.toContain("#0a0818\" stroke");
  });
});


describe("validatePublish: 連戦(場面)", () => {
  const waveSurvive = (o: object = {}) => ({ kind: "survive", durationSec: 20, emitters: [em({ e: 20 })], ...o });
  const waveBoss = (o: object = {}) => ({ kind: "boss", durationSec: 60, bossHp: 400, bossMove: 1, emitters: [em()], ...o });
  const seq = (waves: unknown[], over: object = {}) => ({
    name: "連戦", authorName: "K", mode: "sequence", durationSec: 0, emitters: [], waves, clearReplay: "AQIDBAUGBwg=", ...over,
  });
  const total = (n: number, d: number) => d + 2 * (n - 1);

  it("正しい連戦(雑魚 → 中ボス → 大ボス)を通し、合計の時間が一致している", () => {
    const waves = [waveSurvive(), waveBoss({ durationSec: 30, bossHp: 200 }), waveBoss({ durationSec: 90, bossHp: 800, warning: true, defeat: 3 })];
    const r = validatePublish(seq(waves, { durationSec: total(3, 20 + 30 + 90) }));
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.stage.waves).toHaveLength(3);
      expect(r.stage.waves![2]!.warning).toBe(true);
      expect(r.stage.waves![2]!.defeat).toBe(3);
      expect(r.stage.emitters).toEqual([]);
    }
  });
  it("合計の時間が合わない・場面が0または7つ・不正な種類は拒否", () => {
    expect(validatePublish(seq([waveSurvive()], { durationSec: 21 }))).toEqual({ ok: false, error: "duration" });
    expect(validatePublish(seq([]))).toEqual({ ok: false, error: "wave-count" });
    expect(validatePublish(seq(Array.from({ length: 7 }, () => waveSurvive()), { durationSec: 140 + 12 }))).toEqual({ ok: false, error: "wave-count" });
    expect(validatePublish(seq([{ ...waveSurvive(), kind: "x" }], { durationSec: 20 }))).toEqual({ ok: false, error: "wave-kind" });
  });
  it("場面ごとの範囲を検証する(時間・HP・生き残りにHP、警告は、ボスだけ)", () => {
    expect(validatePublish(seq([waveSurvive({ durationSec: 25 })], { durationSec: 25 }))).toEqual({ ok: false, error: "wave-duration" });
    expect(validatePublish(seq([waveBoss({ durationSec: 0 })], { durationSec: 0 }))).toEqual({ ok: false, error: "wave-duration" });
    expect(validatePublish(seq([waveBoss({ bossHp: 425 })], { durationSec: 60 }))).toEqual({ ok: false, error: "wave-boss-hp" });
    expect(validatePublish(seq([waveSurvive({ bossHp: 400 })], { durationSec: 20 }))).toEqual({ ok: false, error: "wave-boss-hp" });
    expect(validatePublish(seq([waveSurvive({ warning: true })], { durationSec: 20 }))).toEqual({ ok: false, error: "wave-warning" });
    expect(validatePublish(seq([waveSurvive({ defeat: 2 })], { durationSec: 20 }))).toEqual({ ok: false, error: "wave-defeat" });
    expect(validatePublish(seq([waveBoss({ defeat: 9 })], { durationSec: 60 }))).toEqual({ ok: false, error: "wave-defeat" });
  });
  it("爆発(標準)の指定は保存しない。生き残りの場面では、好きな場所からの発射は使えない", () => {
    const r = validatePublish(seq([waveBoss({ defeat: 1 })], { durationSec: 60 }));
    expect(r.ok && "defeat" in r.stage.waves![0]!).toBe(false);
    expect(validatePublish(seq([waveSurvive({ emitters: [em({ p: 1 })] })], { durationSec: 20 }))).toEqual({ ok: false, error: "emitter-point" });
    expect(validatePublish(seq([waveBoss({ emitters: [em({ p: 1 })] })], { durationSec: 60 })).ok).toBe(true);
  });
  it("連戦以外に waves をつけたら拒否。連戦の外側の発射台は空であること", () => {
    expect(validatePublish(good({ waves: [waveSurvive()] }))).toEqual({ ok: false, error: "waves" });
    expect(validatePublish(seq([waveSurvive()], { durationSec: 20, emitters: [em()] }))).toEqual({ ok: false, error: "emitter-count" });
  });
  it("ボス戦・ダメージ勝負の警告と、ボス戦の撃破の演出", () => {
    const b = validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1, bossWarning: true, bossDefeat: 4 }));
    expect(b.ok && b.stage.bossWarning).toBe(true);
    expect(b.ok && b.stage.bossDefeat).toBe(4);
    const std = validatePublish(good({ mode: "boss", durationSec: 60, bossHp: 400, bossMove: 1, bossDefeat: 1 }));
    expect(std.ok && "bossDefeat" in std.stage).toBe(false);
    expect(validatePublish(good({ bossWarning: true }))).toEqual({ ok: false, error: "warning" });
    expect(validatePublish(good({ mode: "damage", durationSec: 60, bossMove: 0, bossDefeat: 2 }))).toEqual({ ok: false, error: "defeat" });
  });
  it("連戦のOGP画像と共有ページが作れる", () => {
    const r = validatePublish(seq([waveSurvive(), waveBoss()], { durationSec: total(2, 80) }));
    if (!r.ok) throw new Error("invalid");
    expect(ogpSvg(r.stage, "ABCDE")).toContain("WAVES");
    const html = renderSharePage({ id: "ABCDE", stage: { ...r.stage, plays: 0, clears: 0, likes: 0 } as never, lang: "ja", origin: "https://x.example", appStoreUrl: "https://a.example" });
    expect(html.status).toBe(200);
    expect(html.html).toContain("連戦 2場面");
  });
});

describe("撃ち方・ボスの大きさと見た目・雑魚・パターンの回転", () => {
  const boss = (o: object = {}) => good({ mode: "boss", durationSec: 60, bossHp: 300, bossMove: 0, emitters: [em({ ph: 0 })], ...o });

  it("撃ち方はステージに入る。標準は入れない。知らない値は拒否", () => {
    const a = validatePublish(good({ shot: "heavy" }));
    expect(a.ok && a.stage.shot).toBe("heavy");
    const b = validatePublish(good({ shot: "standard" }));
    expect(b.ok && "shot" in b.stage).toBe(false);
    expect(validatePublish(good({ shot: "laser" }))).toEqual({ ok: false, error: "shot" });
  });

  it("発射間隔は15秒まで(以前は2秒まで)。弾の形(くの字=1・丸=2)は見た目だけで、標準(未指定・0)は入れない", () => {
    const at = (o: object) => validatePublish(good({ emitters: [em(o)] }));
    const slow = at({ i: 15 });
    expect(slow.ok && slow.stage.emitters[0]!.i).toBe(15);
    expect(at({ i: 2.5 }).ok).toBe(true);
    for (const bad of [15.01, 16, 0.04, 0]) expect(at({ i: bad })).toEqual({ ok: false, error: "emitter-range" });
    const hook = at({ sh: 1 });
    expect(hook.ok && hook.stage.emitters[0]!.sh).toBe(1);
    const round = at({ sh: 2 });
    expect(round.ok && round.stage.emitters[0]!.sh).toBe(2);
    for (const none of [0, undefined, null]) {
      const r = at({ sh: none });
      expect(r.ok && "sh" in r.stage.emitters[0]!).toBe(false);
    }
    for (const bad of [3, -1, 1.5, "1"]) expect(at({ sh: bad })).toEqual({ ok: false, error: "emitter-range" });
  });

  it("毎日のごほうびの演出は、種類ごとに1つまで受け付け、種類の順に並べる。称号・範囲外・重複は拒否", () => {
    const a = validatePublish(good({ rewardFx: [13, 6] }));   // オーラ(13)・火花(6)
    expect(a.ok && a.stage.rewardFx).toEqual([6, 13]);
    const none = validatePublish(good({ rewardFx: [] }));
    expect(none.ok && "rewardFx" in none.stage).toBe(false);
    const plain = validatePublish(good({}));
    expect(plain.ok && "rewardFx" in plain.stage).toBe(false);
    for (const bad of [[4], [365], [-1], [1.5], ["1"], [5, 10], [0, 1, 2, 3, 8], "abc", 3]) {
      expect(validatePublish(good({ rewardFx: bad }))).toEqual({ ok: false, error: "reward-fx" });
    }
  });

  it("一覧のプレビュー: 開始秒は長さの30%まで(切り捨て)。0と未指定は入れない。「見せない」と同時には指定できない", () => {
    const a = validatePublish(good({ durationSec: 20, previewStart: 6 }));   // 20秒の30% = 6秒
    expect(a.ok && a.stage.previewStart).toBe(6);
    for (const v of [0, undefined, null]) {
      const r = validatePublish(good({ durationSec: 20, previewStart: v }));
      expect(r.ok && "previewStart" in r.stage).toBe(false);
    }
    const c = validatePublish(good({ durationSec: 10, previewStart: 3 }));   // 10秒の30% = 3秒
    expect(c.ok && c.stage.previewStart).toBe(3);
    for (const bad of [7, -1, 1.5, "3", NaN]) {
      expect(validatePublish(good({ durationSec: 20, previewStart: bad }))).toEqual({ ok: false, error: "preview" });
    }
    const n = validatePublish(good({ noPreview: true }));
    expect(n.ok && n.stage.noPreview).toBe(true);
    const off = validatePublish(good({ noPreview: false }));
    expect(off.ok && "noPreview" in off.stage).toBe(false);
    expect(validatePublish(good({ noPreview: "yes" }))).toEqual({ ok: false, error: "preview" });
    expect(validatePublish(good({ noPreview: true, previewStart: 3 }))).toEqual({ ok: false, error: "preview" });
  });

  it("ボスの大きさ(小・大)と見た目を受け付け、標準(中・見た目0)は入れない", () => {
    const a = validatePublish(boss({ bossSize: 0, bossLook: 3, mooks: 2, mookLook: 4 }));
    expect(a.ok && [a.stage.bossSize, a.stage.bossLook, a.stage.mooks, a.stage.mookLook]).toEqual([0, 3, 2, 4]);
    const b = validatePublish(boss({ bossSize: 1, bossLook: 0 }));
    expect(b.ok && ("bossSize" in b.stage || "bossLook" in b.stage)).toBe(false);
  });

  it("ボスのないステージには、ボスの大きさ・見た目は付けられない。範囲外も拒否", () => {
    expect(validatePublish(good({ bossSize: 2 }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(good({ bossLook: 2 }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(boss({ bossSize: 3 }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(boss({ bossLook: 6 }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(good({ mookLook: 2 }))).toEqual({ ok: false, error: "look" });   // 雑魚を出さないのに、見た目だけは付けられない
  });

  it("堕天使(ボスの見た目5)は、大きさ・動きを使わないものだけ受け付ける。ボスのないステージには付けられない", () => {
    const a = validatePublish(boss({ bossLook: 5, bossMove: 0 }));
    expect(a.ok && a.stage.bossLook).toBe(5);
    expect(validatePublish(boss({ bossLook: 5, bossMove: 1 }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(boss({ bossLook: 5, bossMove: 0, bossSize: 2 }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(good({ bossLook: 5 }))).toEqual({ ok: false, error: "look" });
  });

  it("覚醒する段階(2か3)は、ボス戦だけ受け付ける", () => {
    const a = validatePublish(boss({ bossLook: 5, bossMove: 0, awaken: 3 }));
    expect(a.ok && a.stage.awaken).toBe(3);
    const b = validatePublish(boss({}));
    expect(b.ok && "awaken" in b.stage).toBe(false);
    for (const bad of [1, 4, 0, "2", 2.5]) expect(validatePublish(boss({ awaken: bad }))).toEqual({ ok: false, error: "look" });
    expect(validatePublish(good({ awaken: 2 }))).toEqual({ ok: false, error: "look" });
  });

  it("堕天使の技は、堕天使(bossLook 5)のボスにだけ置ける", () => {
    const angel = (t: string) => ({ emitters: [em({ t })] });
    for (const t of ["angelTwin", "angelFeather", "angelHalo", "angelCross", "angelParadise"]) {
      const ok = validatePublish(boss({ ...angel(t), bossLook: 5, bossMove: 0 }));
      expect(ok.ok && ok.stage.emitters[0]!.t).toBe(t);
      expect(validatePublish(boss({ ...angel(t), bossLook: 2 }))).toEqual({ ok: false, error: "emitter-pattern" });
      expect(validatePublish(boss(angel(t)))).toEqual({ ok: false, error: "emitter-pattern" });
      expect(validatePublish(good(angel(t)))).toEqual({ ok: false, error: "emitter-pattern" });
    }
    // 連戦では、堕天使の場面にだけ
    const wave = (look: number | undefined, t: string) => ({ kind: "boss", durationSec: 30, bossHp: 100, bossMove: look === 5 ? 0 : 1, emitters: [em({ t })], ...(look !== undefined ? { bossLook: look } : {}) });
    const seq = (waves: unknown[]) => validatePublish({
      name: "連戦", authorName: "K", mode: "sequence", durationSec: 30 * waves.length + 2 * (waves.length - 1), emitters: [], waves, clearReplay: "AQIDBAUGBwg=",
    } as never);
    expect(seq([wave(5, "angelHalo")]).ok).toBe(true);
    expect(seq([wave(undefined, "angelHalo")])).toEqual({ ok: false, error: "emitter-pattern" });
    expect(seq([wave(5, "angelHalo"), wave(3, "angelTwin")])).toEqual({ ok: false, error: "emitter-pattern" });
  });

  it("パターンの回転は -180〜180 度。回せないパターンには付けられない", () => {
    const a = validatePublish(good({ emitters: [em({ a: 45 })] }));
    expect(a.ok && a.stage.emitters[0]!.a).toBe(45);
    const b = validatePublish(good({ emitters: [em({ a: 0 })] }));
    expect(b.ok && "a" in b.stage.emitters[0]!).toBe(false);
    expect(validatePublish(good({ emitters: [em({ a: 200 })] }))).toEqual({ ok: false, error: "emitter-range" });
    expect(validatePublish(good({ emitters: [em({ t: "rain", a: 15 })] }))).toEqual({ ok: false, error: "emitter-range" });
  });
});

describe("validateDisplayName(ランキング・コメントに出す投稿者名)", () => {
  it("未指定・空は匿名(undefined)として受け付ける", () => {
    for (const v of [undefined, null, "", "   "]) expect(validateDisplayName(v)).toEqual({ ok: true, name: undefined });
  });
  it("前後の空白を除き、1〜12文字を受け付ける", () => {
    expect(validateDisplayName("  こうしん ")).toEqual({ ok: true, name: "こうしん" });
    expect(validateDisplayName("あ".repeat(12))).toEqual({ ok: true, name: "あ".repeat(12) });
  });
  it("13文字以上・文字列以外・NGワードは拒否", () => {
    expect(validateDisplayName("あ".repeat(13))).toEqual({ ok: false });
    expect(validateDisplayName(123)).toEqual({ ok: false });
    expect(validateDisplayName("しね")).toEqual({ ok: false });
  });
});

describe("quota(1日の公開数の上限)", () => {
  const user = (o: Record<string, unknown>) => ({ get: (k: string) => o[k] });
  const NOW = Date.UTC(2026, 9, 30, 3, 0, 0);   // 日本時間 12:00
  it("日本時間の0時で日付が変わる", () => {
    expect(jstDay(Date.UTC(2026, 9, 30, 14, 59, 59))).toBe(jstDay(Date.UTC(2026, 9, 30, 0, 0, 0)));
    expect(jstDay(Date.UTC(2026, 9, 30, 15, 0, 0))).toBe(jstDay(Date.UTC(2026, 9, 30, 0, 0, 0)) + 1);
  });
  it("無料は5本まで。追加券ぶんだけ増え、使うと減る", () => {
    let q = readQuota(user({}), NOW);
    for (let i = 0; i < FREE_DAILY_POSTS; i++) { expect(checkPost(q, false)).toBe("ok"); q = afterPost(q, false); }
    expect(checkPost(q, false)).toBe("daily-limit");
    q = afterGrant(q)!;
    expect(checkPost(q, false)).toBe("ok");
    q = afterPost(q, false);
    expect(q.extra).toBe(0);
    expect(checkPost(q, false)).toBe("daily-limit");
  });
  it("購入者は券を使わず、絶対上限まで投稿できる", () => {
    let q = readQuota(user({ postDay: jstDay(NOW), postsToday: 8, extraPosts: 3 }), NOW);
    expect(checkPost(q, true)).toBe("ok");
    q = afterPost(q, true);
    expect(q.extra).toBe(3);
    expect(checkPost({ ...q, used: HARD_DAILY_POSTS }, true)).toBe("daily-limit");
  });
  it("日付が変わると今日の数は0、追加券は持ち越す。持てる枚数と今日の取得数に上限がある", () => {
    const q = readQuota(user({ postDay: jstDay(NOW) - 1, postsToday: 7, extraPosts: 2, grantsToday: 20 }), NOW);
    expect(q).toMatchObject({ used: 0, extra: 2, grants: 0 });
    expect(afterGrant({ ...q, extra: MAX_EXTRA_TICKETS })).toBeNull();
    expect(afterGrant({ ...q, grants: 25 })).toBeNull();
    expect(readQuota(user({ extraPosts: 999 }), NOW).extra).toBe(MAX_EXTRA_TICKETS);
    expect(readQuota(user({ postDay: "x", postsToday: "y" }), NOW)).toMatchObject({ used: 0, extra: 0 });
  });
});

describe("custompath(描いた軌道)", () => {
  it("2〜60点、偶数個の数、範囲内だけ受け付け、0.1刻みに丸める", () => {
    expect(validatePath([0, 0, 10.04, -5.05])).toEqual([0, 0, 10, -5.1]);
    expect(validatePath([0, 0])).toBeNull();                       // 1点だけ
    expect(validatePath([0, 0, 1])).toBeNull();                    // 奇数個
    expect(validatePath(Array(122).fill(1))).toBeNull();           // 61点
    expect(validatePath(Array(120).fill(1))).not.toBeNull();       // 60点
    expect(validatePath([0, 0, 601, 0])).toBeNull();
    expect(validatePath([0, 0, NaN, 0])).toBeNull();
    expect(validatePath([0, 0, "1", 0])).toBeNull();
    expect(validatePath("abc")).toBeNull();
    expect(Object.is(validatePath([0, 0, -0.04, 0])![2], 0)).toBe(true);   // -0 にならない
  });
  it("時間に沿って線の上を進み、最後の点を過ぎたら最後の速さで進み続ける", () => {
    const p = [0, 0, 10, 0, 10, 20];   // 0.1秒ごとに右へ10、そのあと下へ20
    expect(pathPosition(p, 0)).toEqual({ x: 0, y: 0 });
    expect(pathPosition(p, 0.05)).toEqual({ x: 5, y: 0 });
    expect(pathPosition(p, 0.1)).toEqual({ x: 10, y: 0 });
    const mid = pathPosition(p, 0.15);
    expect(mid.x).toBeCloseTo(10, 9);
    expect(mid.y).toBeCloseTo(10, 9);
    const late = pathPosition(p, 0.3);                       // 下へ 200px/秒 のまま
    expect(late.x).toBeCloseTo(10, 9);
    expect(late.y).toBeCloseTo(20 + 200 * 0.1, 9);
  });
});

describe("search(ステージ名の検索)", () => {
  it("全角/半角・大文字小文字・カタカナ/ひらがな・空白の違いを無くす", () => {
    expect(normalizeName("ＮＥＯＮ ネオン")).toBe("neonねおん");
    expect(normalizeName("ボス戦")).toBe("ぼす戦");
    expect(normalizeName("Ｒａｉｎ　Ｒａｉｎ")).toBe("rainrain");
  });
  it("名前から、1文字と2文字の手がかりを作る(重複なし)", () => {
    expect(nameKeys("あいあ").sort()).toEqual(["あ", "あい", "い", "いあ"].sort());
    expect(nameKeys("").length).toBe(0);
    expect(nameKeys("あ".repeat(100)).length).toBeLessThanOrEqual(80);
  });
  it("検索語の手がかりは、2文字以上なら先頭の2文字、1文字ならその文字。長すぎる・空は使えない", () => {
    expect(queryGram("ネオンの渦")).toEqual({ norm: "ねおんの渦", gram: "ねお" });
    expect(queryGram("渦")).toEqual({ norm: "渦", gram: "渦" });
    expect(queryGram("  ")).toBeNull();
    expect(queryGram("あ".repeat(21))).toBeNull();
    // 手がかりは、その名前に保存される手がかりに必ず含まれる(部分一致で見つかる)
    expect(nameKeys("きれいなネオンの渦")).toContain(queryGram("ネオン")!.gram);
  });
});

describe("validatePublish(描いた軌道の弾幕)", () => {
  it("custom には軌道が必須で、0.1刻みに丸めて保存される。ほかのパターンに軌道は付けられない", () => {
    const ok = validatePublish(good({ emitters: [em({ t: "custom", path: [0, 0, 10.04, 5.06, 20, 10] })] }));
    expect(ok.ok && ok.stage.emitters[0]!.path).toEqual([0, 0, 10, 5.1, 20, 10]);
    const noPath = validatePublish(good({ emitters: [em({ t: "custom" })] }));
    expect(noPath).toEqual({ ok: false, error: "emitter-path" });
    const onRing = validatePublish(good({ emitters: [em({ t: "ring", path: [0, 0, 1, 1] })] }));
    expect(onRing).toEqual({ ok: false, error: "emitter-path" });
    for (const bad of [[0, 0], [0, 0, 1], [0, 0, 700, 0], [0, 0, "a", 0], Array(122).fill(0)]) {
      expect(validatePublish(good({ emitters: [em({ t: "custom", path: bad })] }))).toEqual({ ok: false, error: "emitter-path" });
    }
  });
  it("広告で解放するパターンも受け付ける", () => {
    for (const t of ["twinRing", "lightRain", "helix", "chargeBeam", "boomerang", "giantOrb", "sweepLaser", "mine", "meteor", "gridLaser", "gravity", "orbit", "snake", "bubble"]) expect(validatePublish(good({ emitters: [em({ t })] })).ok).toBe(true);
  });
});

describe("notify", () => {
  it("遊ばれた回数の節目を越えたときだけ返す", () => {
    expect(crossedMilestone(9, 10)).toBe(10);
    expect(crossedMilestone(10, 11)).toBeUndefined();
    expect(crossedMilestone(0, 3)).toBeUndefined();
    expect(crossedMilestone(45, 120)).toBe(100);   // いちどに2つ越えたら、大きいほう
    expect(crossedMilestone(999, 1000)).toBe(1000);
  });

  it("言語は、知らないものは英語、地域付きは近いものにする", () => {
    expect(pushLang("ja")).toBe("ja");
    expect(pushLang("ja-JP")).toBe("ja");
    expect(pushLang("zh-Hant-TW")).toBe("zh-Hant");
    expect(pushLang("zh-CN")).toBe("zh-Hans");
    expect(pushLang("pt-PT")).toBe("pt-BR");
    expect(pushLang("it")).toBe("en");
    expect(pushLang(undefined)).toBe("en");
  });

  it("文面にステージ名とコメントを入れ、長いものは切る", () => {
    expect(pushText("ja", "likes", "花火")).toEqual({ title: "いいねされました", body: "「花火」にいいねが付きました" });
    expect(pushText("en", "plays", "Storm", "100").body).toBe('"Storm" has been played 100 times');
    expect(pushText("ja", "likes", "  ").body).toBe("「名前のないステージ」にいいねが付きました");
    const long = pushText("ja", "comments", "a".repeat(40), "b".repeat(80)).body;
    expect(long).toBe(`「${"a".repeat(30)}…」にコメント: ${"b".repeat(60)}…`);
  });
});

describe("チャージビームの当たり判定", () => {
  const beam = (o: object = {}) => ({ x: 100, y: 100, vx: 0, vy: 1, age: 1.0, bounces: 1, ...o });
  it("撃っている間だけ、光線の太さの内側で当たる", () => {
    expect(beamHits(beam({ age: 0.99 }), 100, 300)).toBe(false);
    expect(beamHits(beam(), 100, 300)).toBe(true);
    expect(beamHits(beam(), 108, 400)).toBe(true);
    expect(beamHits(beam(), 110, 400)).toBe(false);
  });
  it("出る場所より後ろには伸びず、一度当たったビームはもう当たらない", () => {
    expect(beamHits(beam(), 100, 80)).toBe(false);
    expect(beamHits(beam({ bounces: 0 }), 100, 300)).toBe(false);
  });
});

describe("爆風(隕石・地雷)の当たり判定", () => {
  const blast = (o: object = {}) => ({ x: 100, y: 100, age: 1.1, bounces: 1, radius: 34, fuse: 1.1, ...o });
  it("予告のあとだけ、半径の内側で当たり、1回で終わる", () => {
    expect(blastHits(blast({ age: 1.0 }), 100, 100)).toBe(false);
    expect(blastHits(blast(), 130, 100)).toBe(true);
    expect(blastHits(blast(), 145, 100)).toBe(false);
    expect(blastHits(blast({ bounces: 0 }), 100, 100)).toBe(false);
  });
});

describe("友達招待の部品", () => {
  it("招待コードは、小文字・空白・ハイフンを直して読み、紛らわしい文字(0/O/1/I)を含むものは断る", async () => {
    const { normalizeCode, isValidCode } = await import("../src/invite.js");
    expect(normalizeCode(" abcd-efgh ")).toBe("ABCDEFGH");
    expect(isValidCode("ABCDEFGH")).toBe(true);
    for (const bad of ["ABCDEFG", "ABCDEFGHJ", "ABCDEFG0", "ABCDEFGO", "ABCDEFG1", "ABCDEFGI", "", normalizeCode(undefined)]) expect(isValidCode(bad)).toBe(false);
  });
  it("DeviceCheck の署名つきトークンは、ES256 で、鍵 ID とチーム ID が入る", async () => {
    const { generateKeyPairSync, verify } = await import("node:crypto");
    const { deviceCheckJwt } = await import("../src/invite.js");
    const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
    const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    const jwt = deviceCheckJwt(pem, "KEY1234567", "TEAM123456", 1_700_000_000);
    const [h, b, sig] = jwt.split(".") as [string, string, string];
    expect(JSON.parse(Buffer.from(h, "base64url").toString())).toEqual({ alg: "ES256", kid: "KEY1234567", typ: "JWT" });
    expect(JSON.parse(Buffer.from(b, "base64url").toString())).toEqual({ iss: "TEAM123456", iat: 1_700_000_000 });
    expect(verify("sha256", Buffer.from(`${h}.${b}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(sig, "base64url"))).toBe(true);
  });
  it("DeviceCheck: 設定が足りなければ判定しない。設定があれば、記録なし=未使用・bit0=使用済みを読み分ける", async () => {
    const { generateKeyPairSync } = await import("node:crypto");
    const { deviceGateFromEnv } = await import("../src/invite.js");
    expect(deviceGateFromEnv({})).toBeNull();
    const pem = generateKeyPairSync("ec", { namedCurve: "P-256" }).privateKey.export({ type: "pkcs8", format: "pem" }).toString();
    const env = { DEVICECHECK_P8: Buffer.from(pem).toString("base64"), DEVICECHECK_KEY_ID: "K", DEVICECHECK_TEAM_ID: "T" };
    const calls: { url: string; body: Record<string, unknown> }[] = [];
    const reply = (status: number, text: string) => (async (url: unknown, init: { body: string }) => { calls.push({ url: String(url), body: JSON.parse(init.body) }); return { status, text: async () => text } as Response; }) as unknown as typeof fetch;
    expect(await deviceGateFromEnv(env, reply(200, "Failed to find bit state"))!.used("tok")).toBe(false);
    expect(await deviceGateFromEnv(env, reply(200, JSON.stringify({ bit0: true, bit1: false, last_update_time: "2026-11" })))!.used("tok")).toBe(true);
    await deviceGateFromEnv(env, reply(200, ""))!.mark("tok");
    expect(calls[0]!.url).toBe("https://api.devicecheck.apple.com/v1/query_two_bits");
    expect(calls[2]!.url).toBe("https://api.devicecheck.apple.com/v1/update_two_bits");
    expect(calls[2]!.body).toMatchObject({ device_token: "tok", bit0: true, bit1: false });
    await expect(deviceGateFromEnv(env, reply(401, "bad"))!.used("tok")).rejects.toThrow();
  });
});
