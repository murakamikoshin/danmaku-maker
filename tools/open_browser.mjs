// 画面付きの Chrome を Playwright で開き、指定の URL を表示したまま待機する。
// ログイン状態は ~/.local/danmaku-browser に残る。後から connectOverCDP('http://localhost:9222') で接続して操作できる。
// 使い方: node tools/open_browser.mjs https://github.com/login
import { chromium } from '../web-tests/node_modules/@playwright/test/index.mjs';
import os from 'node:os';

const url = process.argv[2] ?? 'https://github.com/login';
const ctx = await chromium.launchPersistentContext(`${os.homedir()}/.local/danmaku-browser`, {
  channel: 'chrome', headless: false, viewport: null,
  args: ['--remote-debugging-port=9222'],
});
const page = ctx.pages()[0] ?? await ctx.newPage();
await page.goto(url);
console.log('opened', page.url());
await new Promise(() => {});
