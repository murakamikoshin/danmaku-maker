import { expect, test } from "@playwright/test";

const PAGES = ["/ja/", "/en/", "/ja/terms", "/en/terms", "/ja/privacy", "/en/privacy", "/ja/support", "/en/support"];

test.describe("規約・プライバシー・サポートページ", () => {
  for (const p of PAGES) {
    test(`${p} が表示でき、リンク切れが無く、スマホ幅で読める`, async ({ browser, request }) => {
      const ctx = await browser.newContext({ viewport: { width: 375, height: 700 }, deviceScaleFactor: 2 });
      const page = await ctx.newPage();
      const res = await page.goto(p);
      expect(res!.status()).toBe(200);
      await expect(page.locator("h1")).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0);
      const hrefs = await page.locator("a[href]").evaluateAll((as) => as.map((a) => (a as HTMLAnchorElement).getAttribute("href")!));
      for (const h of hrefs) {
        if (h.startsWith("mailto:") || h.startsWith("http")) continue;
        const r = await request.get(h);
        expect(r.status(), `${p} → ${h}`).toBe(200);
      }
      if (p.endsWith("terms") || p.endsWith("privacy")) await page.screenshot({ path: `test-results/${p.replace(/\//g, "_")}.png`, fullPage: true });
      await ctx.close();
    });
  }

  test("プライバシーポリシーに、実際に使うサービスが書かれている", async ({ page }) => {
    await page.goto("/en/privacy");
    const text = await page.locator("main").innerText();
    for (const w of ["Firebase", "Sign in with Apple", "AdMob", "RevenueCat", "advertising identifier"]) expect(text).toContain(w);
    await page.goto("/ja/privacy");
    const ja = await page.locator("main").innerText();
    for (const w of ["Firebase", "Sign in with Apple", "AdMob", "RevenueCat", "広告識別子", "アカウントを削除"]) expect(ja).toContain(w);
  });

  test("利用規約に、UGC の扱い・禁止事項・通報・停止が書かれている", async ({ page }) => {
    await page.goto("/ja/terms");
    const text = await page.locator("main").innerText();
    for (const w of ["禁止事項", "通報", "ブロック", "アカウントの停止", "投稿されたステージ"]) expect(text).toContain(w);
  });

  test("存在しないページは 404 ページ", async ({ page }) => {
    const res = await page.goto("/nope");
    expect(res!.status()).toBe(404);
  });

  test("ルートは言語ごとのページへ移動する", async ({ browser }) => {
    const ctx = await browser.newContext({ locale: "ja-JP" });
    const page = await ctx.newPage();
    await page.goto("/");
    await page.waitForURL("**/ja/");
    await ctx.close();
  });
});
