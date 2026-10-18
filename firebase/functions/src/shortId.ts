import { randomInt } from "node:crypto";

/** 0/O、1/I/L など紛らわしい文字を除いた 31 文字 */
export const ID_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const ID_LENGTH = 5;

export function newShortId(): string {
  let s = "";
  for (let i = 0; i < ID_LENGTH; i++) s += ID_ALPHABET[randomInt(ID_ALPHABET.length)];
  return s;
}

export function isValidShortId(id: unknown): id is string {
  return typeof id === "string" && id.length === ID_LENGTH && [...id].every((c) => ID_ALPHABET.includes(c));
}

/** 入力されたIDを正規化する（小文字・紛らわしい文字の読み替え） */
export function normalizeShortId(input: string): string {
  return input.trim().toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1");
}
