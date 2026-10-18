import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall, onRequest, type CallableRequest } from "firebase-functions/v2/https";
import { renderOgp } from "./ogp.js";
import { isValidShortId, newShortId, normalizeShortId } from "./shortId.js";
import { pickLang, renderSharePage } from "./share.js";
import { REPORT_REASONS, validatePublish, type Stage } from "./validate.js";

setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });
initializeApp();
const db = getFirestore();

const APP_STORE_URL = process.env.APP_STORE_URL ?? "https://apps.apple.com/";
const HIDE_REPORT_THRESHOLD = 5;
const POST_INTERVAL_MS = 10_000;
const TREND_HALF_LIFE_MS = 2 * 24 * 3600 * 1000;

/** Sign in with Apple などでログイン済み（匿名ではない）ユーザーの uid を返す */
function requireMember(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "sign-in-required");
  if (req.auth.token.firebase?.sign_in_provider === "anonymous") throw new HttpsError("unauthenticated", "sign-in-required");
  return req.auth.uid;
}

function requireAny(req: CallableRequest): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "auth-required");
  return req.auth.uid;
}

function stageIdFrom(data: unknown): string {
  const raw = typeof (data as { stageId?: unknown })?.stageId === "string" ? (data as { stageId: string }).stageId : "";
  const id = normalizeShortId(raw);
  if (!isValidShortId(id)) throw new HttpsError("invalid-argument", "stage-id");
  return id;
}

const decay = (value: number, from: number, now: number) => value * 0.5 ** ((now - from) / TREND_HALF_LIFE_MS);

async function saveOgp(id: string, stage: Stage): Promise<string> {
  const path = `og/${id}.png`;
  await getStorage().bucket().file(path).save(renderOgp(stage, id), {
    contentType: "image/png",
    metadata: { cacheControl: "public, max-age=31536000, immutable" },
  });
  return path;
}

export const publishStage = onCall({ memory: "512MiB", timeoutSeconds: 60 }, async (req) => {
  const uid = requireMember(req);
  const v = validatePublish(req.data);
  if (!v.ok) throw new HttpsError("invalid-argument", v.error);
  if ((req.data as { termsAccepted?: unknown }).termsAccepted !== true) throw new HttpsError("failed-precondition", "terms-not-accepted");
  const langRaw = (req.data as { lang?: unknown }).lang;
  const lang = typeof langRaw === "string" && /^[a-z]{2,3}(-[A-Za-z0-9]{2,8})?$/.test(langRaw) ? langRaw : "und";

  const userRef = db.doc(`users/${uid}`);
  const user = await userRef.get();
  const last = user.get("lastPostAt")?.toMillis?.() ?? 0;
  if (Date.now() - last < POST_INTERVAL_MS) throw new HttpsError("resource-exhausted", "too-fast");
  if (user.get("banned") === true) throw new HttpsError("permission-denied", "banned");

  const now = Date.now();
  let id = "";
  for (let attempt = 0; attempt < 10; attempt++) {
    const candidate = newShortId();
    try {
      await db.doc(`stages/${candidate}`).create({
        authorUid: uid, ...v.stage, ogImagePath: "", status: "published",
        plays: 0, clears: 0, likes: 0, reports: 0, clearRate: 0, trending: 0, trendUpdatedAt: now,
        createdAt: FieldValue.serverTimestamp(), lang,
      });
      id = candidate;
      break;
    } catch (e) {
      if ((e as { code?: number }).code === 6) continue; // ALREADY_EXISTS: IDが衝突したので引き直す
      throw e;
    }
  }
  if (!id) throw new HttpsError("internal", "id-exhausted");

  await db.doc(`stageReplays/${id}`).set({ authorUid: uid, clearReplay: v.clearReplay, createdAt: FieldValue.serverTimestamp() });
  await userRef.set({
    displayName: v.stage.authorName, postCount: FieldValue.increment(1), lastPostAt: FieldValue.serverTimestamp(),
    createdAt: user.exists ? user.get("createdAt") : FieldValue.serverTimestamp(),
    blockedUids: user.exists ? user.get("blockedUids") ?? [] : [],
  }, { merge: true });

  try {
    await db.doc(`stages/${id}`).update({ ogImagePath: await saveOgp(id, v.stage) });
  } catch (e) {
    logger.error("ogp-failed", { id, error: String(e) }); // 画像は後から ogImage 関数が作り直す
  }
  return { id };
});

export const submitResults = onCall(async (req) => {
  requireAny(req);
  const results = (req.data as { results?: unknown })?.results;
  if (!Array.isArray(results) || results.length < 1 || results.length > 30) throw new HttpsError("invalid-argument", "results");
  const merged = new Map<string, { plays: number; clears: number }>();
  for (const r of results) {
    const id = normalizeShortId(String((r as { stageId?: unknown })?.stageId ?? ""));
    const plays = (r as { plays?: unknown })?.plays, clears = (r as { clears?: unknown })?.clears;
    if (!isValidShortId(id) || !Number.isInteger(plays) || !Number.isInteger(clears)) throw new HttpsError("invalid-argument", "result-entry");
    const p = plays as number, c = clears as number;
    if (p < 0 || p > 100 || c < 0 || c > p) throw new HttpsError("invalid-argument", "result-range");
    const cur = merged.get(id) ?? { plays: 0, clears: 0 };
    merged.set(id, { plays: cur.plays + p, clears: cur.clears + c });
  }
  for (const [id, add] of merged) {
    await db.runTransaction(async (tx) => {
      const ref = db.doc(`stages/${id}`);
      const snap = await tx.get(ref);
      if (!snap.exists || snap.get("status") !== "published") return;
      const now = Date.now();
      const plays = (snap.get("plays") as number) + add.plays;
      const clears = Math.min(plays, (snap.get("clears") as number) + add.clears);
      const rate = plays > 0 ? clears / plays : 0;
      const trending = decay(snap.get("trending") ?? 0, snap.get("trendUpdatedAt") ?? now, now) + add.plays + add.clears * 2;
      tx.update(ref, { plays, clears, clearRate: rate, hardRate: plays >= 10 ? rate : FieldValue.delete(), trending, trendUpdatedAt: now });
    });
  }
  return { ok: true };
});

export const toggleLike = onCall(async (req) => {
  const uid = requireMember(req);
  const id = stageIdFrom(req.data);
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`stages/${id}`), likeRef = db.doc(`stages/${id}/likes/${uid}`);
    const [stage, like] = await Promise.all([tx.get(ref), tx.get(likeRef)]);
    if (!stage.exists || stage.get("status") !== "published") throw new HttpsError("not-found", "stage");
    const now = Date.now();
    const trending = decay(stage.get("trending") ?? 0, stage.get("trendUpdatedAt") ?? now, now);
    const liked = !like.exists;
    if (liked) tx.set(likeRef, { createdAt: FieldValue.serverTimestamp() }); else tx.delete(likeRef);
    const likes = Math.max(0, (stage.get("likes") as number) + (liked ? 1 : -1));
    tx.update(ref, { likes, trending: trending + (liked ? 5 : 0), trendUpdatedAt: now });
    return { liked, likes };
  });
});

export const reportStage = onCall(async (req) => {
  const uid = requireMember(req);
  const id = stageIdFrom(req.data);
  const reason = (req.data as { reason?: unknown }).reason;
  if (!(REPORT_REASONS as readonly unknown[]).includes(reason)) throw new HttpsError("invalid-argument", "reason");
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`stages/${id}`), repRef = db.doc(`reports/${id}_${uid}`);
    const [stage, rep] = await Promise.all([tx.get(ref), tx.get(repRef)]);
    if (!stage.exists) throw new HttpsError("not-found", "stage");
    if (rep.exists) return { already: true, hidden: stage.get("status") === "hidden" };
    const reports = (stage.get("reports") as number) + 1;
    const hide = reports >= HIDE_REPORT_THRESHOLD && stage.get("status") === "published";
    tx.set(repRef, { stageId: id, reporterUid: uid, reason, createdAt: FieldValue.serverTimestamp() });
    tx.update(ref, { reports, ...(hide ? { status: "hidden" } : {}) });
    if (hide) {
      tx.set(db.collection("admin_alerts").doc(), { type: "auto-hidden", stageId: id, reports, createdAt: FieldValue.serverTimestamp() });
      logger.error("stage-auto-hidden", { stageId: id, reports }); // Cloud Monitoring のログベースアラートで通知する
    }
    return { already: false, hidden: hide };
  });
});

/** /s/{id} … OGP つきの共有ページ */
export const sharePage = onRequest(async (req, res) => {
  const lang = pickLang(req.get("accept-language"), typeof req.query.lang === "string" ? req.query.lang : undefined);
  const id = normalizeShortId(req.path.split("/").filter(Boolean).pop() ?? "");
  const origin = `${req.get("x-forwarded-proto")?.split(",")[0] ?? "https"}://${req.get("x-forwarded-host") ?? req.get("host")}`;
  let stage = null;
  if (isValidShortId(id)) {
    const snap = await db.doc(`stages/${id}`).get();
    if (snap.exists && snap.get("status") === "published") stage = snap.data() as never;
  }
  const page = renderSharePage({ id, stage, lang, origin, appStoreUrl: APP_STORE_URL });
  res.status(page.status).set("Content-Type", "text/html; charset=utf-8").set("Vary", "Accept-Language")
    .set("Cache-Control", page.status === 200 ? "public, max-age=300, s-maxage=600" : "public, max-age=60").send(page.html);
});

/** /og/{id}.png … OGP 画像。無ければ作り直して保存する */
export const ogImage = onRequest({ memory: "512MiB" }, async (req, res) => {
  const id = normalizeShortId((req.path.split("/").filter(Boolean).pop() ?? "").replace(/\.png$/i, ""));
  if (!isValidShortId(id)) { res.status(404).send("not found"); return; }
  const file = getStorage().bucket().file(`og/${id}.png`);
  let png: Buffer;
  if ((await file.exists())[0]) {
    png = (await file.download())[0];
  } else {
    const snap = await db.doc(`stages/${id}`).get();
    if (!snap.exists || snap.get("status") !== "published") { res.status(404).send("not found"); return; }
    await saveOgp(id, snap.data() as Stage);
    png = (await file.download())[0];
  }
  res.status(200).set("Content-Type", "image/png").set("Cache-Control", "public, max-age=86400, s-maxage=86400").send(png);
});
