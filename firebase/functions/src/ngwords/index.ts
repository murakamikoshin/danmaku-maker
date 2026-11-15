import { NG_JA } from "./ja.js";
import { NG_EN_SUBSTRINGS, NG_EN_WORDS } from "./en.js";

const LEET: Record<string, string> = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i" };

/** カタカナ → ひらがな */
function toHiragana(s: string): string {
  return s.replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60));
}

/**
 * 見えない文字(ゼロ幅スペース・方向の制御・異体字セレクタ・ハングルの埋め草など)。
 * 「し\u200bね」のように間に挟んで、NGワードやURLの検査をすり抜けるのを防ぐため、比べる前に取り除く
 */
const INVISIBLE_RE = /[\p{Cf}\u115F\u1160\u3164\uFFA0]|\u034F|\p{Variation_Selector}/gu;
export const stripInvisible = (text: string): string => text.replace(INVISIBLE_RE, "");

/** 全角・半角、大小文字、カタカナ、長音などを揃える(見えない文字も取り除く) */
export function normalize(text: string): string {
  return toHiragana(stripInvisible(text.normalize("NFKC")).toLowerCase()).replace(/ー/g, "ー");
}

export function containsNgWord(text: string): boolean {
  const base = normalize(text);
  // 日本語: 空白や記号を抜いた形(文字と数字だけ)でも調べる(「し ね」「し.ね」「し♪ね」「し/ね」対策)
  const squeezed = base.replace(/[^\p{L}\p{N}]+/gu, "");
  if (NG_JA.some((w) => squeezed.includes(w) || base.includes(w))) return true;

  // 英語: leet 変換 → 単語境界つき
  const leet = base.replace(/[013457@$!]/g, (c) => LEET[c] ?? c);
  const latinSqueezed = leet.replace(/[^a-z]+/g, "");
  if (NG_EN_SUBSTRINGS.some((w) => latinSqueezed.includes(w) || base.includes(w))) return true;
  const words = leet.split(/[^a-z]+/).filter(Boolean);
  return words.some((w) => NG_EN_WORDS.includes(w));
}
