import type { Firestore } from "firebase-admin/firestore";

/** 検索用に、名前をそろえる: 全角/半角・大文字小文字・カタカナ/ひらがな・空白の違いを無くす */
export function normalizeName(s: string): string {
  return s.normalize("NFKC").toLowerCase()
    .replace(/[ァ-ヶ]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0x60))
    .replace(/\s+/g, "");
}

/** 名前から、検索の手がかり(1文字と2文字の並び)を作る。ステージに保存しておき、検索のときに array-contains で絞る */
export function nameKeys(name: string): string[] {
  const chars = [...normalizeName(name)].slice(0, 40);
  const keys = new Set<string>();
  for (let i = 0; i < chars.length; i++) {
    keys.add(chars[i]!);
    if (i + 1 < chars.length) keys.add(chars[i]! + chars[i + 1]!);
  }
  return [...keys].slice(0, 80);
}

/** 検索語から、絞り込みに使う手がかりを選ぶ(2文字以上なら先頭の2文字、1文字ならその1文字)。使えない語は null */
export function queryGram(query: string): { norm: string; gram: string } | null {
  const chars = [...normalizeName(query)];
  if (chars.length < 1 || chars.length > 20) return null;
  return { norm: chars.join(""), gram: chars.length >= 2 ? chars[0]! + chars[1]! : chars[0]! };
}

const DONE_DOC = "meta/nameKeysBackfill";

/**
 * 検索の手がかり(nameKeys)がまだ無い、これまでのステージに付ける。全部に付け終わったら記録して、以後は何もしない。
 * 返すのは、付けたステージの数
 */
export async function backfillNameKeys(db: Firestore, pageSize = 200): Promise<number> {
  if ((await db.doc(DONE_DOC).get()).exists) return 0;
  let updated = 0;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = db.collection("stages").orderBy("__name__").limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    for (const doc of snap.docs) {
      if (Array.isArray(doc.get("nameKeys"))) continue;
      const name = doc.get("name");
      await doc.ref.update({ nameKeys: nameKeys(typeof name === "string" ? name : "") });
      updated++;
    }
    if (snap.size < pageSize) break;
    last = snap.docs[snap.docs.length - 1];
  }
  await db.doc(DONE_DOC).set({ doneAt: Date.now(), updated });
  return updated;
}
