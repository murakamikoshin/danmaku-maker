import { describe, expect, it } from "vitest";
import { FEEDBACK_DAILY_LIMIT, FEEDBACK_INTERVAL_MS, FEEDBACK_MAX_LENGTH, FEEDBACK_RECIPIENTS, validateFeedback } from "../src/feedback.js";

describe("要望フォームの検証", () => {
  const ok = { text: "ボスをもっと増やしてほしいです", contact: "", app: "1.1.3", os: "17.2", lang: "ja" };
  it("ふつうの要望は通り、前後の空白は取る", () => {
    expect(validateFeedback({ ...ok, text: "  ボスをもっと増やしてほしいです \n" })?.text).toBe("ボスをもっと増やしてほしいです");
  });
  it("短すぎる・長すぎる・文字でないものは断る", () => {
    expect(validateFeedback({ ...ok, text: "あ" })).toBeNull();
    expect(validateFeedback({ ...ok, text: "     " })).toBeNull();
    expect(validateFeedback({ ...ok, text: "あ".repeat(FEEDBACK_MAX_LENGTH + 1) })).toBeNull();
    expect(validateFeedback({ ...ok, text: "あ".repeat(FEEDBACK_MAX_LENGTH) })).not.toBeNull();
    expect(validateFeedback({ ...ok, text: 123 })).toBeNull();
    expect(validateFeedback(null)).toBeNull();
    expect(validateFeedback("text")).toBeNull();
  });
  it("返信先は任意で、長すぎるものは断る。端末情報は短く切る", () => {
    expect(validateFeedback({ ...ok, contact: "a@example.com" })?.contact).toBe("a@example.com");
    expect(validateFeedback({ ...ok, contact: "x".repeat(101) })).toBeNull();
    expect(validateFeedback({ ...ok, app: "x".repeat(100) })?.app.length).toBe(20);
    expect(validateFeedback({ text: ok.text })).toEqual({ text: ok.text, contact: "", app: "", os: "", lang: "" });
  });
  it("転送先と制限の値", () => {
    expect(FEEDBACK_RECIPIENTS).toEqual(["koushin0224@icloud.com", "koshinstudio88@gmail.com"]);
    expect(FEEDBACK_INTERVAL_MS).toBe(60_000);
    expect(FEEDBACK_DAILY_LIMIT).toBe(5);
  });
});
