import { NG_JA } from "./ja.js";
import { NG_EN_SUBSTRINGS, NG_EN_WORDS } from "./en.js";

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i" };

/** カタカナ → ひらがな */
function toHiragana(s: string): string {
  return s.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));
}

/** 全角・半角、大小文字、カタカナ、長音などを揃える */
export function normalize(text: string): string {
  return toHiragana(text.normalize("NFKC").toLowerCase()).replace(/ー/g, "ー");
}

export function containsNgWord(text: string): boolean {
  const base = normalize(text);
  // 日本語: 空白や記号を抜いた形でも調べる（「し ね」「し.ね」対策）
  const squeezed = base.replace(/[\s._\-*・、。,!！?？~〜]+/g, "");
  if (NG_JA.some((w) => squeezed.includes(w) || base.includes(w))) return true;

  // 英語: leet 変換 → 単語境界つき
  const leet = base.replace(/[013457@$!]/g, (c) => LEET[c] ?? c);
  const latinSqueezed = leet.replace(/[^a-z]+/g, "");
  if (NG_EN_SUBSTRINGS.some((w) => latinSqueezed.includes(w) || base.includes(w))) return true;
  const words = leet.split(/[^a-z]+/).filter(Boolean);
  return words.some((w) => NG_EN_WORDS.includes(w));
}
