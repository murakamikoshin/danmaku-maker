// 要望フォーム: 保存・メール転送・間隔と1日の上限を、エミュレーターで確かめる
import { getFirestore as adminDb } from "firebase-admin/firestore";
import { initializeApp as adminInit } from "firebase-admin/app";
import { describe, expect, it } from "vitest";
import { FEEDBACK_DAILY_LIMIT, FEEDBACK_INTERVAL_MS, FEEDBACK_RECIPIENTS, submitFeedback } from "../../src/feedback.js";

process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
const db = adminDb(adminInit({ projectId: "demo-danmaku" }, "feedback-admin"));
const body = { text: "ボスをもっと増やしてほしいです", contact: "me@example.com", app: "1.1.3", os: "17.2", lang: "ja" };
const errCode = async (p: Promise<unknown>) => { try { await p; return null; } catch (e) { return (e as { message: string }).message; } };

describe("要望フォーム", () => {
  it("保存してから、設定された転送先へメールを送る", async () => {
    const uid = `f${Date.now()}`;
    const sent: { to: string[]; subject: string; body: string }[] = [];
    const mailer = { send: async (to: string[], subject: string, b: string) => { sent.push({ to, subject, body: b }); } };
    expect(await submitFeedback(db, uid, body, Date.now(), mailer)).toEqual({ mailed: true });
    expect(sent).toHaveLength(1);
    expect(sent[0]!.to).toEqual(FEEDBACK_RECIPIENTS);
    expect(sent[0]!.body).toContain("ボスをもっと増やしてほしいです");
    expect(sent[0]!.body).toContain("me@example.com");
    const saved = await db.collection("feedback").where("uid", "==", uid).get();
    expect(saved.size).toBe(1);
    expect(saved.docs[0]!.get("mailed")).toBe(true);
  });
  it("メールの設定がなくても、送信に失敗しても、要望は残る", async () => {
    const a = `f${Date.now()}a`, b = `f${Date.now()}b`;
    expect(await submitFeedback(db, a, body, Date.now(), null)).toEqual({ mailed: false });
    expect(await submitFeedback(db, b, body, Date.now(), { send: async () => { throw new Error("smtp down"); } })).toEqual({ mailed: false });
    for (const u of [a, b]) {
      const s = await db.collection("feedback").where("uid", "==", u).get();
      expect(s.size).toBe(1);
      expect(s.docs[0]!.get("mailed")).toBe(false);
    }
  });
  it("続けては送れず、1日の上限もある。日が変われば戻る", async () => {
    const uid = `f${Date.now()}c`;
    const t0 = Date.UTC(2026, 10, 10, 3, 0);   // 日本時間 12:00
    await submitFeedback(db, uid, body, t0, null);
    expect(await errCode(submitFeedback(db, uid, body, t0 + 1000, null))).toBe("too-fast");
    for (let i = 1; i < FEEDBACK_DAILY_LIMIT; i++) await submitFeedback(db, uid, body, t0 + i * FEEDBACK_INTERVAL_MS, null);
    expect(await errCode(submitFeedback(db, uid, body, t0 + FEEDBACK_DAILY_LIMIT * FEEDBACK_INTERVAL_MS, null))).toBe("daily-limit");
    await submitFeedback(db, uid, body, t0 + 24 * 3600_000, null);   // 翌日
    expect((await db.collection("feedback").where("uid", "==", uid).get()).size).toBe(FEEDBACK_DAILY_LIMIT + 1);
  });
  it("おかしな入力は保存しない", async () => {
    const uid = `f${Date.now()}d`;
    expect(await errCode(submitFeedback(db, uid, { text: "あ" }, Date.now(), null))).toBe("feedback");
    expect((await db.collection("feedback").where("uid", "==", uid).get()).size).toBe(0);
  });
});
