import { defineConfig } from "@playwright/test";

const JAVA_HOME = process.env.JAVA_HOME ?? `${process.env.HOME}/.local/jdk-dl/jdk-21.0.12.1+1/Contents/Home`;

// Hosting / Functions / Firestore / Storage のエミュレーターを立てて、実際のブラウザ(Chrome)で確認する。
// この Mac(macOS 13)では Playwright 同梱の Chromium が使えないため、インストール済みの Chrome を使う。
export default defineConfig({
  testDir: "./tests",
  timeout: 60_000,
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  globalSetup: "./global-setup.ts",
  use: {
    baseURL: "http://127.0.0.1:5000",
    channel: process.env.CI ? undefined : "chrome",
    screenshot: "off",
  },
  webServer: {
    command: "cd ../firebase && (cd functions && npm run build) && firebase emulators:start --only hosting,functions,firestore,storage --project demo-danmaku",
    url: "http://127.0.0.1:5000/ja/",
    reuseExistingServer: true,
    timeout: 180_000,
    env: { JAVA_HOME, PATH: `${JAVA_HOME}/bin:${process.env.PATH}` },
  },
});
