import type { Firestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions/v2";

/**
 * 作者への通知(いいね・コメント・遊ばれた回数の節目)。
 * 通知を受け取る端末は users/{uid}/pushDevices/{端末ID} に、アプリが書く(トークン・言語・種類ごとのオン/オフ)。
 * 種類ごとのオン/オフは端末ごと。オフの種類は送らない。
 */
export const PUSH_KINDS = ["likes", "comments", "plays"] as const;
export type PushKind = (typeof PUSH_KINDS)[number];

/** 遊ばれた回数が、この数を超えたときに知らせる */
export const PLAY_MILESTONES = [10, 50, 100, 500, 1000, 5000, 10000, 50000, 100000] as const;

/** 同じステージへのいいねの通知は、この間隔より短いと送らない(いいねが続いたときに、通知が鳴りっぱなしにならないように) */
export const LIKE_THROTTLE_MS = 10 * 60 * 1000;

/** before から after に増えたときに、越えた節目(いちばん大きいもの)。越えていなければ undefined */
export function crossedMilestone(before: number, after: number): number | undefined {
  let hit: number | undefined;
  for (const m of PLAY_MILESTONES) if (before < m && after >= m) hit = m;
  return hit;
}

const LANGS = ["ja", "en", "zh-Hans", "zh-Hant", "ko", "es", "fr", "de", "pt-BR", "ru"] as const;
type Lang = (typeof LANGS)[number];

export function pushLang(lang: unknown): Lang {
  if (typeof lang !== "string") return "en";
  if ((LANGS as readonly string[]).includes(lang)) return lang as Lang;
  const l = lang.toLowerCase();
  if (l.startsWith("zh")) return l.includes("hant") || l.includes("tw") || l.includes("hk") ? "zh-Hant" : "zh-Hans";
  if (l.startsWith("pt")) return "pt-BR";
  const base = l.split(/[-_]/)[0];
  return (LANGS as readonly string[]).includes(base) ? (base as Lang) : "en";
}

type Text = { title: string; body: (name: string, extra: string) => string };
const TEXTS: Record<Lang, Record<PushKind, Text>> = {
  ja: {
    likes: { title: "いいねされました", body: (n) => `「${n}」にいいねが付きました` },
    comments: { title: "コメントが付きました", body: (n, x) => `「${n}」にコメント: ${x}` },
    plays: { title: "たくさん遊ばれています", body: (n, x) => `「${n}」が${x}回遊ばれました` },
  },
  en: {
    likes: { title: "New like", body: (n) => `Someone liked "${n}"` },
    comments: { title: "New comment", body: (n, x) => `New comment on "${n}": ${x}` },
    plays: { title: "Your stage is popular", body: (n, x) => `"${n}" has been played ${x} times` },
  },
  "zh-Hans": {
    likes: { title: "收到点赞", body: (n) => `「${n}」收到了一个赞` },
    comments: { title: "收到评论", body: (n, x) => `「${n}」有新评论：${x}` },
    plays: { title: "你的关卡很受欢迎", body: (n, x) => `「${n}」已被游玩${x}次` },
  },
  "zh-Hant": {
    likes: { title: "收到按讚", body: (n) => `「${n}」收到了一個讚` },
    comments: { title: "收到留言", body: (n, x) => `「${n}」有新留言：${x}` },
    plays: { title: "你的關卡很受歡迎", body: (n, x) => `「${n}」已被遊玩${x}次` },
  },
  ko: {
    likes: { title: "좋아요를 받았어요", body: (n) => `「${n}」에 좋아요가 달렸어요` },
    comments: { title: "댓글이 달렸어요", body: (n, x) => `「${n}」에 댓글: ${x}` },
    plays: { title: "스테이지가 인기예요", body: (n, x) => `「${n}」이(가) ${x}번 플레이되었어요` },
  },
  es: {
    likes: { title: "Nuevo me gusta", body: (n) => `A alguien le gustó "${n}"` },
    comments: { title: "Nuevo comentario", body: (n, x) => `Nuevo comentario en "${n}": ${x}` },
    plays: { title: "Tu nivel es popular", body: (n, x) => `"${n}" se ha jugado ${x} veces` },
  },
  fr: {
    likes: { title: "Nouveau j'aime", body: (n) => `Quelqu'un a aimé « ${n} »` },
    comments: { title: "Nouveau commentaire", body: (n, x) => `Nouveau commentaire sur « ${n} » : ${x}` },
    plays: { title: "Ton niveau a du succès", body: (n, x) => `« ${n} » a été joué ${x} fois` },
  },
  de: {
    likes: { title: "Neues Like", body: (n) => `Jemandem gefällt „${n}“` },
    comments: { title: "Neuer Kommentar", body: (n, x) => `Neuer Kommentar zu „${n}“: ${x}` },
    plays: { title: "Deine Stage ist beliebt", body: (n, x) => `„${n}“ wurde ${x}-mal gespielt` },
  },
  "pt-BR": {
    likes: { title: "Nova curtida", body: (n) => `Alguém curtiu "${n}"` },
    comments: { title: "Novo comentário", body: (n, x) => `Novo comentário em "${n}": ${x}` },
    plays: { title: "Sua fase está popular", body: (n, x) => `"${n}" foi jogada ${x} vezes` },
  },
  ru: {
    likes: { title: "Новый лайк", body: (n) => `Кому-то понравился «${n}»` },
    comments: { title: "Новый комментарий", body: (n, x) => `Новый комментарий к «${n}»: ${x}` },
    plays: { title: "Ваш уровень популярен", body: (n, x) => `«${n}» сыграли ${x} раз` },
  },
};

const UNNAMED: Record<Lang, string> = {
  ja: "名前のないステージ", en: "Untitled stage", "zh-Hans": "未命名关卡", "zh-Hant": "未命名關卡", ko: "이름 없는 스테이지",
  es: "Nivel sin nombre", fr: "Niveau sans nom", de: "Unbenannte Stage", "pt-BR": "Fase sem nome", ru: "Безымянный уровень",
};

const clip = (s: string, max: number) => ([...s].length > max ? [...s].slice(0, max).join("") + "…" : s);

/** 通知の文面(ステージ名とコメントは長すぎると切る) */
export function pushText(lang: unknown, kind: PushKind, stageName: string, extra = ""): { title: string; body: string } {
  const l = pushLang(lang);
  const name = clip(stageName.trim() || UNNAMED[l], 30);
  const t = TEXTS[l][kind];
  return { title: t.title, body: t.body(name, clip(extra, 60)) };
}

export type NotifyEvent = {
  /** 通知を受け取る人(ステージの作者) */
  to: string;
  /** いいね・コメントをした人(作者本人と、作者がブロックした人のときは送らない) */
  from?: string;
  kind: PushKind;
  stageId: string;
  stageName: string;
  extra?: string;
};

/** 送ってよいか(本人の操作でないか・ブロックしていないか・間を空けたか)を確かめて、通知を送る。失敗しても例外は投げない */
export async function notifyAuthor(db: Firestore, e: NotifyEvent, now = Date.now()): Promise<number> {
  try {
    if (!e.to || (e.from && e.from === e.to)) return 0;
    const devices = await db.collection(`users/${e.to}/pushDevices`).get();
    const targets = devices.docs.filter((d) => d.get("enabled") === true && d.get(e.kind) !== false && typeof d.get("token") === "string");
    if (targets.length === 0) return 0;
    if (e.from) {
      const user = await db.doc(`users/${e.to}`).get();
      const blocked = user.get("blockedUids");
      if (Array.isArray(blocked) && blocked.includes(e.from)) return 0;
    }
    if (e.kind === "likes") {
      const ref = db.doc(`users/${e.to}/pushThrottle/${e.stageId}_${e.kind}`);
      const ok = await db.runTransaction(async (tx) => {
        const last = ((await tx.get(ref)).get("lastAt") as number | undefined) ?? 0;
        if (now - last < LIKE_THROTTLE_MS) return false;
        tx.set(ref, { lastAt: now });
        return true;
      });
      if (!ok) return 0;
    }
    const res = await getMessaging().sendEach(targets.map((d) => {
      const { title, body } = pushText(d.get("lang"), e.kind, e.stageName, e.extra);
      return {
        token: d.get("token") as string,
        notification: { title, body },
        data: { stageId: e.stageId, kind: e.kind },
        apns: { payload: { aps: { sound: "default" } } },
      };
    }));
    // 使えなくなったトークン(アプリを消した端末など)は消す
    await Promise.all(res.responses.map(async (r, i) => {
      const code = r.error?.code ?? "";
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token" || code === "messaging/invalid-argument") {
        await targets[i].ref.delete();
      }
    }));
    return res.successCount;
  } catch (err) {
    logger.warn("notify-failed", { kind: e.kind, stageId: e.stageId, error: String(err) });
    return 0;
  }
}
