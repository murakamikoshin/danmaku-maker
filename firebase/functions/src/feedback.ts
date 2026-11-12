import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * アプリの「要望を送る」。受け取った内容は必ず feedback コレクションに残し、メールの送信設定があれば転送もする。
 * 送れなくても要望は失われない(Firestore に残る)。
 */

/** 転送先 */
export const FEEDBACK_RECIPIENTS = ["koushin0224@icloud.com", "koshinstudio88@gmail.com"];
export const FEEDBACK_MAX_LENGTH = 1000;
export const FEEDBACK_MIN_LENGTH = 5;
const CONTACT_MAX = 100;
/** 同じ人が続けて送れる間隔と、1 日の上限 */
export const FEEDBACK_INTERVAL_MS = 60_000;
export const FEEDBACK_DAILY_LIMIT = 5;

export interface FeedbackInput { text: string; contact: string; app: string; os: string; lang: string }

/** 入力を検証して整える。おかしければ null */
export function validateFeedback(raw: unknown): FeedbackInput | null {
  if (typeof raw !== "object" || raw === null) return null;
  const o = raw as Record<string, unknown>;
  const text = typeof o.text === "string" ? o.text.trim() : "";
  if ([...text].length < FEEDBACK_MIN_LENGTH || [...text].length > FEEDBACK_MAX_LENGTH) return null;
  const contact = typeof o.contact === "string" ? o.contact.trim() : "";
  if ([...contact].length > CONTACT_MAX) return null;
  const small = (v: unknown, max: number) => (typeof v === "string" ? v.slice(0, max) : "");
  return { text, contact, app: small(o.app, 20), os: small(o.os, 20), lang: small(o.lang, 20) };
}

export interface Mailer { send(to: string[], subject: string, body: string): Promise<void> }

/** 要望を受け付ける。間隔・上限は uid ごと。メールの送信に失敗しても、要望は残る */
export async function submitFeedback(db: Firestore, uid: string, raw: unknown, nowMs: number, mailer: Mailer | null): Promise<{ mailed: boolean }> {
  const input = validateFeedback(raw);
  if (!input) throw new HttpsError("invalid-argument", "feedback");
  const limitRef = db.doc(`feedbackLimits/${uid}`);
  const day = new Date(nowMs + 9 * 3600_000).toISOString().slice(0, 10);   // 日本時間の日付
  await db.runTransaction(async (tx) => {
    const s = await tx.get(limitRef);
    const last = (s.get("last") as number | undefined) ?? 0;
    const sameDay = s.get("day") === day;
    const count = sameDay ? ((s.get("count") as number | undefined) ?? 0) : 0;
    if (nowMs - last < FEEDBACK_INTERVAL_MS) throw new HttpsError("resource-exhausted", "too-fast");
    if (count >= FEEDBACK_DAILY_LIMIT) throw new HttpsError("resource-exhausted", "daily-limit");
    tx.set(limitRef, { last: nowMs, day, count: count + 1 });
  });
  const ref = await db.collection("feedback").add({ uid, ...input, createdAt: FieldValue.serverTimestamp(), mailed: false });
  if (!mailer) return { mailed: false };
  const subject = `【弾幕メーカー】要望: ${[...input.text].slice(0, 30).join("")}`;
  const body = `${input.text}\n\n---\n返信先: ${input.contact || "(未入力)"}\nuid: ${uid}\nアプリ: ${input.app}  iOS: ${input.os}  言語: ${input.lang}\nID: ${ref.id}`;
  try {
    await mailer.send(FEEDBACK_RECIPIENTS, subject, body);
    await ref.update({ mailed: true });
    return { mailed: true };
  } catch (e) {
    // 送信に失敗しても要望は feedback に残っている。原因が分かるよう、ログには残す(パスワードなどは含まれない)
    const err = e as { code?: string; responseCode?: number; message?: string };
    console.error("feedback mail failed", { id: ref.id, code: err.code, responseCode: err.responseCode, message: String(err.message ?? "").slice(0, 200) });
    return { mailed: false };
  }
}
