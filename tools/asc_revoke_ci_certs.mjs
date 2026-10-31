// GitHub Actions の TestFlight ビルドが作った開発用の証明書を、App Store Connect API で取り消す。
// GitHub の Mac は毎回まっさらなので、xcodebuild -allowProvisioningUpdates がビルドのたびに証明書を新しく作り、
// アカウントの上限に達するとビルドできなくなる(2026-10-31)。
// 取り消すのは、名前に「Created via API」が付く開発用の証明書だけ(手元の Mac で Xcode が作った証明書は消さない)。
// 使い方: ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH(.p8 のパス)を環境変数で渡して node tools/asc_revoke_ci_certs.mjs
import { createSign } from "node:crypto";
import { readFileSync } from "node:fs";

const { ASC_KEY_ID: kid, ASC_ISSUER_ID: iss, ASC_KEY_PATH: keyPath } = process.env;
if (!kid || !iss || !keyPath) { console.log("ASC の鍵がないので、何もしない"); process.exit(0); }

const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
const now = Math.floor(Date.now() / 1000);
const head = b64({ alg: "ES256", kid, typ: "JWT" }), body = b64({ iss, iat: now, exp: now + 600, aud: "appstoreconnect-v1" });
const sig = createSign("SHA256").update(`${head}.${body}`).sign({ key: readFileSync(keyPath, "utf8"), dsaEncoding: "ieee-p1363" }).toString("base64url");
const auth = { Authorization: `Bearer ${head}.${body}.${sig}` };
const API = "https://api.appstoreconnect.apple.com/v1";

const res = await fetch(`${API}/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200`, { headers: auth });
if (!res.ok) { console.log("証明書の一覧を取れなかった:", res.status, await res.text()); process.exit(0); }
const certs = (await res.json()).data ?? [];
console.log(`開発用の証明書: ${certs.length} 個`);
let revoked = 0;
for (const c of certs) {
  const a = c.attributes ?? {};
  const label = `${a.displayName ?? ""} / ${a.name ?? ""}`;
  const fromCI = /created via api/i.test(label);
  console.log(`  ${fromCI ? "取り消す" : "残す    "}  ${label}  (期限 ${a.expirationDate ?? "?"})`);
  if (!fromCI) continue;
  const del = await fetch(`${API}/certificates/${c.id}`, { method: "DELETE", headers: auth });
  if (del.ok || del.status === 204) revoked++;
  else console.log(`    取り消せなかった: ${del.status} ${await del.text()}`);
}
console.log(`取り消した数: ${revoked}`);
