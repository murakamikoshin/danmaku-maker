import { describe, expect, it } from "vitest";
import { decideLatest, isOlder, storeVersion } from "../src/appversion.js";

describe("App Store の版から、アップデートの案内の版を決める", () => {
  it("版は数字ごとに比べる(アプリの UpdateChecker.isOlder と同じ)", () => {
    expect(isOlder("1.9.2", "1.10.0")).toBe(true);
    expect(isOlder("1.4.0", "1.4")).toBe(false);
    expect(isOlder("1.4", "1.4.1")).toBe(true);
    expect(isOlder("2.0.0", "1.99.0")).toBe(false);
  });
  it("日本とアメリカで同じ新しい版が出たときだけ上げる", () => {
    expect(decideLatest("1.4.0", ["1.4.1", "1.4.1"])).toBe("1.4.1");
    expect(decideLatest("", ["1.4.0", "1.4.0"])).toBe("1.4.0");
    expect(decideLatest("1.4.0", ["1.3.0", "1.4.1"]), "日本がまだ古い").toBeNull();
    expect(decideLatest("1.4.0", [null, "1.4.1"]), "取れない国がある").toBeNull();
  });
  it("下げない・同じなら何もしない・おかしな版は使わない", () => {
    expect(decideLatest("1.4.0", ["1.4.0", "1.4.0"])).toBeNull();
    expect(decideLatest("1.5.0", ["1.4.0", "1.4.0"])).toBeNull();
    expect(decideLatest("1.4.0", ["abc", "abc"])).toBeNull();
    expect(decideLatest("1.4.0", [])).toBeNull();
  });
  it("App Store の公開情報から版を読む。失敗したら null", async () => {
    const ok = (async () => new Response(JSON.stringify({ results: [{ version: "1.4.0" }] }))) as unknown as typeof fetch;
    expect(await storeVersion("jp", ok)).toBe("1.4.0");
    const empty = (async () => new Response(JSON.stringify({ results: [] }))) as unknown as typeof fetch;
    expect(await storeVersion("jp", empty)).toBeNull();
    const down = (async () => new Response("x", { status: 503 })) as unknown as typeof fetch;
    expect(await storeVersion("jp", down)).toBeNull();
    const boom = (async () => { throw new Error("net"); }) as unknown as typeof fetch;
    expect(await storeVersion("jp", boom)).toBeNull();
  });
});
