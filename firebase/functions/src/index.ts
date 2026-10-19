import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger, setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall, onRequest, type CallableRequest } from "firebase-functions/v2/https";
import { decodeReplay, isShotType, simulate } from "./fullsim.js";
import { renderOgp } from "./ogp.js";
import { isValidShortId, newShortId, normalizeShortId } from "./shortId.js";
import { pickLang, renderSharePage } from "./share.js";
import { MAX_REPLAY_CHARS, REPORT_REASONS, timeLimitSec, validateComment, validatePublish, type Stage } from "./validate.js";

setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });
initializeApp();
const db = getFirestore();

const APP_STORE_URL = process.env.APP_STORE_URL ?? "https://apps.apple.com/app/id6824245206";
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
  // 作者のクリア記録を再生して、本当にクリアできるステージか確かめる(テストプレイは標準の撃ち方)
  const maxSteps = (timeLimitSec(v.stage.mode, v.stage.durationSec) + 3) * 120 + 144;
  const played = decodeReplay(v.clearReplay, maxSteps);
  if (!played) throw new HttpsError("invalid-argument", "replay");
  if (simulate(v.stage, played.moves, played.steps, "standard").outcome !== "cleared") throw new HttpsError("invalid-argument", "replay-not-cleared");
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
    const mirrorRef = db.doc(`users/${uid}/likes/${id}`); // アカウント削除のときに、自分のいいねを取り消すための控え
    if (liked) { tx.set(likeRef, { createdAt: FieldValue.serverTimestamp() }); tx.set(mirrorRef, { createdAt: FieldValue.serverTimestamp() }); }
    else { tx.delete(likeRef); tx.delete(mirrorRef); }
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

const SCORE_INTERVAL_MS = 3000;
const HANDLE_CHOICES = 16;

/** uid から決まる 4 桁の数字(同じ名前の人を区別する飾り。uid そのものは分からない) */
function handleNumber(uid: string): number {
  let h = 2166136261;
  for (const ch of uid) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
  return h % 10000;
}

/**
 * ランキングに記録する。アプリから届いた操作記録(リプレイ)をサーバーが再生して、本当にクリアできているか確かめてから載せる。
 * ボス戦は「クリアまでのステップ数」(少ないほど上)、ダメージ勝負は「与えたダメージ」(多いほど上)。標準の撃ち方だけが対象。
 * 名前は自由入力にせず、決まった言葉の組み合わせ(番号で選ぶ)だけにする。
 */
export const submitScore = onCall({ memory: "512MiB", timeoutSeconds: 60 }, async (req) => {
  const uid = requireAny(req);
  const id = stageIdFrom(req.data);
  const d = req.data as { replay?: unknown; shot?: unknown; handle?: { a?: unknown; n?: unknown } };
  if (!isShotType(d.shot) || d.shot !== "standard") throw new HttpsError("invalid-argument", "shot");
  const a = d.handle?.a, n = d.handle?.n;
  if (!Number.isInteger(a) || !Number.isInteger(n) || (a as number) < 0 || (a as number) >= HANDLE_CHOICES || (n as number) < 0 || (n as number) >= HANDLE_CHOICES) {
    throw new HttpsError("invalid-argument", "handle");
  }
  if (typeof d.replay !== "string" || d.replay.length < 8 || d.replay.length > MAX_REPLAY_CHARS || !/^[A-Za-z0-9+/]+={0,2}$/.test(d.replay)) {
    throw new HttpsError("invalid-argument", "replay");
  }

  // 連続送信を防ぐ
  const metaRef = db.doc(`scoreMeta/${uid}`);
  await db.runTransaction(async (tx) => {
    const meta = await tx.get(metaRef);
    const last = (meta.get("lastAt") as number | undefined) ?? 0;
    if (Date.now() - last < SCORE_INTERVAL_MS) throw new HttpsError("resource-exhausted", "too-fast");
    tx.set(metaRef, { lastAt: Date.now() });
  });

  const stageSnap = await db.doc(`stages/${id}`).get();
  if (!stageSnap.exists || stageSnap.get("status") !== "published") throw new HttpsError("not-found", "stage");
  const stage = stageSnap.data() as Stage;
  if (stage.mode === "survive") throw new HttpsError("failed-precondition", "no-ranking");

  const played = decodeReplay(d.replay, (timeLimitSec(stage.mode, stage.durationSec) + 3) * 120 + 144);
  if (!played) throw new HttpsError("invalid-argument", "replay");
  const result = simulate(stage, played.moves, played.steps, "standard");
  if (result.outcome !== "cleared") return { accepted: false, reason: "not-cleared" };

  // ボス戦と連戦は「クリアまでの時間」(短いほど上)、ダメージ勝負は「与えたダメージ」(多いほど上)
  const boss = stage.mode === "boss" || stage.mode === "sequence";
  const value = boss ? result.tick : result.damage;
  const better = (x: number, y: number) => (boss ? x < y : x > y);
  const scoreRef = db.doc(`stages/${id}/scores/${uid}`);
  const { improved, best } = await db.runTransaction(async (tx) => {
    const cur = await tx.get(scoreRef);
    const old = cur.get("value") as number | undefined;
    if (old !== undefined && !better(value, old)) return { improved: false, best: old };
    tx.set(scoreRef, { uid, a, n, num: handleNumber(uid), value, mode: stage.mode, createdAt: FieldValue.serverTimestamp() });
    tx.set(db.doc(`scoreReplays/${id}_${uid}`), { stageId: id, uid, value, replay: d.replay, createdAt: FieldValue.serverTimestamp() });
    return { improved: true, best: value };
  });
  const ahead = await db.collection(`stages/${id}/scores`).where("value", boss ? "<" : ">", best).count().get();
  return { accepted: true, improved, value: best, rank: ahead.data().count + 1 };
});

const COMMENT_INTERVAL_MS = 15_000;
const COMMENT_HIDE_THRESHOLD = 3;

/** ステージにコメントする。Apple でサインインした人だけ。NGワード・URL・連続投稿は拒否する */
export const postComment = onCall(async (req) => {
  const uid = requireMember(req);
  const id = stageIdFrom(req.data);
  const d = req.data as { text?: unknown; handle?: { a?: unknown; n?: unknown } };
  const v = validateComment(d.text);
  if (!v.ok) throw new HttpsError("invalid-argument", v.error);
  const a = d.handle?.a, n = d.handle?.n;
  if (!Number.isInteger(a) || !Number.isInteger(n) || (a as number) < 0 || (a as number) >= HANDLE_CHOICES || (n as number) < 0 || (n as number) >= HANDLE_CHOICES) {
    throw new HttpsError("invalid-argument", "handle");
  }
  const stage = await db.doc(`stages/${id}`).get();
  if (!stage.exists || stage.get("status") !== "published") throw new HttpsError("not-found", "stage");

  const metaRef = db.doc(`commentMeta/${uid}`);
  await db.runTransaction(async (tx) => {
    const meta = await tx.get(metaRef);
    const last = (meta.get("lastAt") as number | undefined) ?? 0;
    if (Date.now() - last < COMMENT_INTERVAL_MS) throw new HttpsError("resource-exhausted", "too-fast");
    tx.set(metaRef, { lastAt: Date.now() });
  });

  const ref = db.collection(`stages/${id}/comments`).doc();
  await ref.set({ uid, a, n, num: handleNumber(uid), text: v.text, status: "published", reports: 0, createdAt: FieldValue.serverTimestamp() });
  return { id: ref.id };
});

/** コメントを消す。コメントした本人と、ステージの作者だけができる */
export const deleteComment = onCall(async (req) => {
  const uid = requireAny(req);
  const id = stageIdFrom(req.data);
  const cid = (req.data as { commentId?: unknown }).commentId;
  if (typeof cid !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(cid)) throw new HttpsError("invalid-argument", "comment-id");
  const [stage, comment] = await Promise.all([db.doc(`stages/${id}`).get(), db.doc(`stages/${id}/comments/${cid}`).get()]);
  if (!stage.exists || !comment.exists) throw new HttpsError("not-found", "comment");
  if (comment.get("uid") !== uid && stage.get("authorUid") !== uid) throw new HttpsError("permission-denied", "not-allowed");
  await comment.ref.delete();
  return { ok: true };
});

/** コメントを通報する。1人1回で、3人が通報すると自動で非表示になる */
export const reportComment = onCall(async (req) => {
  const uid = requireMember(req);
  const id = stageIdFrom(req.data);
  const cid = (req.data as { commentId?: unknown }).commentId;
  const reason = (req.data as { reason?: unknown }).reason;
  if (typeof cid !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(cid)) throw new HttpsError("invalid-argument", "comment-id");
  if (!(REPORT_REASONS as readonly unknown[]).includes(reason)) throw new HttpsError("invalid-argument", "reason");
  return db.runTransaction(async (tx) => {
    const ref = db.doc(`stages/${id}/comments/${cid}`), repRef = db.doc(`commentReports/${id}_${cid}_${uid}`);
    const [comment, rep] = await Promise.all([tx.get(ref), tx.get(repRef)]);
    if (!comment.exists) throw new HttpsError("not-found", "comment");
    if (rep.exists) return { already: true, hidden: comment.get("status") === "hidden" };
    const reports = (comment.get("reports") as number) + 1;
    const hide = reports >= COMMENT_HIDE_THRESHOLD && comment.get("status") === "published";
    tx.set(repRef, { stageId: id, commentId: cid, reporterUid: uid, reason, createdAt: FieldValue.serverTimestamp() });
    tx.update(ref, { reports, ...(hide ? { status: "hidden" } : {}) });
    if (hide) {
      tx.set(db.collection("admin_alerts").doc(), { type: "comment-auto-hidden", stageId: id, commentId: cid, reports, createdAt: FieldValue.serverTimestamp() });
      logger.error("comment-auto-hidden", { stageId: id, commentId: cid, reports });
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

/** アカウント削除。投稿したステージ・リプレイ・OGP画像・いいね・ユーザー情報を消し、認証ユーザーも削除する */
export const deleteAccount = onCall({ timeoutSeconds: 300, memory: "512MiB" }, async (req) => {
  const uid = requireAny(req);
  const bucket = getStorage().bucket();

  const mine = await db.collection("stages").where("authorUid", "==", uid).get();
  for (const s of mine.docs) {
    await db.recursiveDelete(s.ref); // いいねのサブコレクションごと
    await db.doc(`stageReplays/${s.id}`).delete();
    const scoreReplays = await db.collection("scoreReplays").where("stageId", "==", s.id).get();
    for (const r of scoreReplays.docs) await r.ref.delete();
    await bucket.file(`og/${s.id}.png`).delete({ ignoreNotFound: true });
  }

  // 自分のランキング記録(他の人のステージにあるもの)と、その操作記録
  const scores = await db.collectionGroup("scores").where("uid", "==", uid).get();
  for (const sc of scores.docs) await sc.ref.delete();
  const myReplays = await db.collection("scoreReplays").where("uid", "==", uid).get();
  for (const r of myReplays.docs) await r.ref.delete();
  await db.doc(`scoreMeta/${uid}`).delete();
  const myComments = await db.collectionGroup("comments").where("uid", "==", uid).get();
  for (const c of myComments.docs) await c.ref.delete();
  await db.doc(`commentMeta/${uid}`).delete();
  const myCommentReports = await db.collection("commentReports").where("reporterUid", "==", uid).get();
  for (const r of myCommentReports.docs) await r.ref.update({ reporterUid: "deleted" });

  const likes = await db.collection(`users/${uid}/likes`).get();
  for (const l of likes.docs) {
    await db.runTransaction(async (tx) => {
      const ref = db.doc(`stages/${l.id}`);
      const st = await tx.get(ref);
      if (!st.exists) return;
      tx.delete(db.doc(`stages/${l.id}/likes/${uid}`));
      tx.update(ref, { likes: Math.max(0, (st.get("likes") as number) - 1) });
    });
  }

  // 通報の記録は安全のために残すが、通報者は特定できないようにする
  const reports = await db.collection("reports").where("reporterUid", "==", uid).get();
  for (const r of reports.docs) await r.ref.update({ reporterUid: "deleted" });

  await db.recursiveDelete(db.doc(`users/${uid}`));
  await getAuth().deleteUser(uid);
  logger.info("account-deleted", { stages: mine.size, likes: likes.size });
  return { ok: true, stages: mine.size };
});
