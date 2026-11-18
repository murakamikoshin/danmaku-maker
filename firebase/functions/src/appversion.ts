import { getRemoteConfig } from "firebase-admin/remote-config";
import { logger } from "firebase-functions/v2";

/**
 * 新しい版が App Store に出たら、Remote Config の update_latest_version を自動でその版にする(アプリの UpdateChecker が読む)。
 * - 日本とアメリカの App Store の両方で、同じ新しい版が出てから書き換える(国ごとに反映が数時間ずれるため。早すぎると、
 *   案内を押しても App Store に新しい版がない)
 * - 上げるだけで、下げない。閉じられない update_min_version は、人が決める(ここでは触らない)
 */
export const APP_STORE_ID = "6824245206";
export const STORE_COUNTRIES = ["jp", "us"] as const;
export const LATEST_KEY = "update_latest_version";

/** 版を数字ごとに比べる(「1.10.0」は「1.9.2」より新しい)。アプリの UpdateChecker.isOlder と同じ */
export function isOlder(a: string, b: string): boolean {
  const x = a.split(".").map((s) => parseInt(s, 10) || 0), y = b.split(".").map((s) => parseInt(s, 10) || 0);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const p = x[i] ?? 0, q = y[i] ?? 0;
    if (p !== q) return p < q;
  }
  return false;
}

const VERSION_RE = /^\d{1,3}(\.\d{1,3}){1,3}$/;

/**
 * 書き換える版を決める。どの国でも同じ版が取れて、それが今の設定より新しいときだけ、その版を返す。
 * 1 つでも取れない国・違う版の国があれば、書き換えない(null)
 */
export function decideLatest(current: string, store: (string | null)[]): string | null {
  if (store.length === 0 || store.some((v) => v === null || !VERSION_RE.test(v))) return null;
  const v = store[0]!;
  if (store.some((s) => s !== v)) return null;
  const cur = current.trim();
  if (cur !== "" && !isOlder(cur, v)) return null;
  return v;
}

/** App Store の公開情報から、その国でいま出ている版を読む(取れなければ null) */
export async function storeVersion(country: string, fetcher: typeof fetch = fetch): Promise<string | null> {
  try {
    const r = await fetcher(`https://itunes.apple.com/lookup?id=${APP_STORE_ID}&country=${country}&t=${Date.now()}`, { signal: AbortSignal.timeout(15_000) });
    if (!r.ok) return null;
    const j = await r.json() as { results?: { version?: unknown }[] };
    const v = j.results?.[0]?.version;
    return typeof v === "string" ? v.trim() : null;
  } catch {
    return null;
  }
}

/** 1 回分: 調べて、必要なら Remote Config を書き換える。書き換えた版を返す(書き換えなければ null) */
export async function syncLatestVersion(): Promise<string | null> {
  const store = await Promise.all(STORE_COUNTRIES.map((c) => storeVersion(c)));
  const rc = getRemoteConfig();
  const template = await rc.getTemplate();
  const param = template.parameters[LATEST_KEY];
  const dv = param?.defaultValue;
  const current = dv && "value" in dv ? dv.value : "";
  const next = decideLatest(current, store);
  if (!next) {
    logger.info("app-version-unchanged", { current, store });
    return null;
  }
  template.parameters[LATEST_KEY] = { ...(param ?? { valueType: "STRING" }), defaultValue: { value: next } };
  await rc.publishTemplate(await rc.validateTemplate(template));
  logger.info("app-version-updated", { from: current, to: next, store });
  return next;
}
