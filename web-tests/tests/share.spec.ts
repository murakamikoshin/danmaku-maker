import { expect, test } from "@playwright/test";
import { STAGE_ID } from "../global-setup";

const meta = (page: import("@playwright/test").Page, sel: string) => page.locator(sel).getAttribute("content");

test.describe("共有ページ /s/{id}", () => {
  test("OGP タグが入っている（日本語）", async ({ browser }) => {
    const ctx = await browser.newContext({ locale: "ja-JP", extraHTTPHeaders: { "Accept-Language": "ja-JP,ja;q=0.9" } });
    const page = await ctx.newPage();
    const res = await page.goto(`/s/${STAGE_ID}`);
    expect(res!.status()).toBe(200);
    expect(await page.getAttribute("html", "lang")).toBe("ja");
    expect(await meta(page, 'meta[property="og:title"]')).toContain("地獄の渦");
    expect(await meta(page, 'meta[property="og:description"]')).toContain("クリア率35%");
    expect(await meta(page, 'meta[property="og:image"]')).toMatch(new RegExp(`/og/${STAGE_ID}\\.png$`));
    expect(await meta(page, 'meta[name="twitter:card"]')).toBe("summary_large_image");
    expect(await meta(page, 'meta[property="og:image:width"]')).toBe("1200");
    // ステージ名の HTML は無害化されて表示される
    await expect(page.locator("h1")).toContainText("<script>x</script>");
    expect(await page.locator("script").count()).toBe(0);
    await ctx.close();
  });

  test("英語の表示（Accept-Language）", async ({ browser }) => {
    const ctx = await browser.newContext({ locale: "en-US", extraHTTPHeaders: { "Accept-Language": "en-US,en;q=0.9" } });
    const page = await ctx.newPage();
    await page.goto(`/s/${STAGE_ID}`);
    expect(await page.getAttribute("html", "lang")).toBe("en");
    await expect(page.getByText("Clear rate")).toBeVisible();
    expect(await meta(page, 'meta[property="og:description"]')).toContain("clear rate");
    await ctx.close();
  });

  test("OGP 画像は 200 で、1200×630 の PNG", async ({ page, request }) => {
    await page.goto(`/s/${STAGE_ID}`);
    const url = await meta(page, 'meta[property="og:image"]');
    const path = new URL(url!).pathname;
    const res = await request.get(path);
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toBe("image/png");
    const buf = await res.body();
    expect(buf.readUInt32BE(16)).toBe(1200);
    expect(buf.readUInt32BE(20)).toBe(630);
  });

  test("存在しない ID は分かりやすい「見つかりません」ページ", async ({ page }) => {
    const res = await page.goto("/s/ZZZZZ", { waitUntil: "domcontentloaded" });
    expect(res!.status()).toBe(404);
    await expect(page.getByRole("heading")).toContainText(/見つかりません|not found/i);
    await expect(page.getByRole("link", { name: /App Store/ })).toBeVisible();
  });

  test("非公開のステージも「見つかりません」", async ({ page }) => {
    const res = await page.goto("/s/HIDD3");
    expect(res!.status()).toBe(404);
  });

  test("スマホ幅でレイアウトが崩れない", async ({ browser }) => {
    const ctx = await browser.newContext({ viewport: { width: 375, height: 700 }, deviceScaleFactor: 2, locale: "ja-JP", extraHTTPHeaders: { "Accept-Language": "ja" } });
    const page = await ctx.newPage();
    await page.goto(`/s/${STAGE_ID}`);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow).toBeLessThanOrEqual(0);
    await page.screenshot({ path: "test-results/share-mobile.png", fullPage: true });
    await ctx.close();
  });
});

test.describe("ユニバーサルリンク", () => {
  for (const p of ["/.well-known/apple-app-site-association", "/apple-app-site-association"]) {
    test(`${p} は JSON で返り、中身が正しい`, async ({ request }) => {
      const res = await request.get(p);
      expect(res.status()).toBe(200);
      expect(res.headers()["content-type"]).toContain("application/json");
      const json = await res.json();
      expect(json.applinks.details[0].appIDs).toEqual(["49Q2CLPBWK.com.koshin.danmakumaker"]);
      expect(json.applinks.details[0].components[0]["/"]).toBe("/s/*");
    });
  }
});
