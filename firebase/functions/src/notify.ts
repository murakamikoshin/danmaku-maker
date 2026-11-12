import type { Firestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions/v2";

/**
 * 作者への通知(いいね・コメント・遊ばれた回数の節目)。
 * 通知を受け取る端末は users/{uid}/pushDevices/{端末ID} に、アプリが書く(トークン・言語・種類ごとのオン/オフ)。
 * 種類ごとのオン/オフは端末ごと。オフの種類は送らない。
 */
export const PUSH_KINDS = ["likes", "comments", "plays", "rewards", "events"] as const;
/** お知らせ(イベント・ランキング戦の開始)。本人がオンにしたときだけ送る(Apple の規定: 宣伝の通知は明示の同意が要る) */
export const OPT_IN_KINDS: readonly PushKind[] = ["events"];
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

const EN_MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const ES_MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
const FR_MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
const DE_MONTHS = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"];
const PT_MONTHS = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"];
const RU_MONTHS = ["январь", "февраль", "март", "апрель", "май", "июнь", "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"];

type Text = { title: string; body: (name: string, extra: string) => string };
const TEXTS: Record<Lang, Record<PushKind, Text>> = {
  ja: {
    likes: { title: "いいねされました", body: (n) => `「${n}」にいいねが付きました` },
    comments: { title: "コメントが付きました", body: (n, x) => `「${n}」にコメント: ${x}` },
    plays: { title: "たくさん遊ばれています", body: (n, x) => `「${n}」が${x}回遊ばれました` },
    rewards: { title: "ごほうびが届きました!", body: (_, x) => (x === "monthly" ? "月間ランキングのごほうびが届きました" : "ともだちが遊んでくれました。ごほうびを受け取ろう") },
    events: { title: "ランキング戦が始まりました!", body: (_, x) => `${x}月のスワイプ弾幕ランキング戦が始まりました!今すぐ参加しよう` },
  },
  en: {
    likes: { title: "New like", body: (n) => `Someone liked "${n}"` },
    comments: { title: "New comment", body: (n, x) => `New comment on "${n}": ${x}` },
    plays: { title: "Your stage is popular", body: (n, x) => `"${n}" has been played ${x} times` },
    rewards: { title: "A reward has arrived!", body: (_, x) => (x === "monthly" ? "Your monthly ranking reward is here" : "Your friend played! Your reward is waiting") },
    events: { title: "The ranking has begun!", body: (_, x) => `The ${EN_MONTHS[Number(x) - 1] ?? ""} Swipe Danmaku ranking has begun! Join now` },
  },
  "zh-Hans": {
    likes: { title: "收到点赞", body: (n) => `「${n}」收到了一个赞` },
    comments: { title: "收到评论", body: (n, x) => `「${n}」有新评论：${x}` },
    plays: { title: "你的关卡很受欢迎", body: (n, x) => `「${n}」已被游玩${x}次` },
    rewards: { title: "奖励已送达！", body: (_, x) => (x === "monthly" ? "月榜奖励已送达" : "好友玩了游戏！快来领取奖励") },
    events: { title: "排名赛开始了！", body: (_, x) => `${x}月的滑动弹幕排名赛开始了！马上参加吧` },
  },
  "zh-Hant": {
    likes: { title: "收到按讚", body: (n) => `「${n}」收到了一個讚` },
    comments: { title: "收到留言", body: (n, x) => `「${n}」有新留言：${x}` },
    plays: { title: "你的關卡很受歡迎", body: (n, x) => `「${n}」已被遊玩${x}次` },
    rewards: { title: "獎勵已送達！", body: (_, x) => (x === "monthly" ? "月榜獎勵已送達" : "好友玩了遊戲！快來領取獎勵") },
    events: { title: "排名賽開始了！", body: (_, x) => `${x}月的滑動彈幕排名賽開始了！馬上參加吧` },
  },
  ko: {
    likes: { title: "좋아요를 받았어요", body: (n) => `「${n}」에 좋아요가 달렸어요` },
    comments: { title: "댓글이 달렸어요", body: (n, x) => `「${n}」에 댓글: ${x}` },
    plays: { title: "스테이지가 인기예요", body: (n, x) => `「${n}」이(가) ${x}번 플레이되었어요` },
    rewards: { title: "보상이 도착했어요!", body: (_, x) => (x === "monthly" ? "월간 랭킹 보상이 도착했어요" : "친구가 플레이했어요! 보상을 받아 보세요") },
    events: { title: "랭킹전이 시작됐어요!", body: (_, x) => `${x}월 스와이프 탄막 랭킹전이 시작됐어요! 지금 참가하세요` },
  },
  es: {
    likes: { title: "Nuevo me gusta", body: (n) => `A alguien le gustó "${n}"` },
    comments: { title: "Nuevo comentario", body: (n, x) => `Nuevo comentario en "${n}": ${x}` },
    plays: { title: "Tu nivel es popular", body: (n, x) => `"${n}" se ha jugado ${x} veces` },
    rewards: { title: "¡Ha llegado una recompensa!", body: (_, x) => (x === "monthly" ? "Tu recompensa del ranking mensual ha llegado" : "¡Tu amigo jugó! Tu recompensa te espera") },
    events: { title: "¡Empieza el ranking!", body: (_, x) => `¡Empieza el ranking de Danmaku Swipe de ${ES_MONTHS[Number(x) - 1] ?? ""}! Participa ya` },
  },
  fr: {
    likes: { title: "Nouveau j'aime", body: (n) => `Quelqu'un a aimé « ${n} »` },
    comments: { title: "Nouveau commentaire", body: (n, x) => `Nouveau commentaire sur « ${n} » : ${x}` },
    plays: { title: "Ton niveau a du succès", body: (n, x) => `« ${n} » a été joué ${x} fois` },
    rewards: { title: "Une récompense est arrivée !", body: (_, x) => (x === "monthly" ? "Ta récompense du classement mensuel est arrivée" : "Ton ami a joué ! Ta récompense t’attend") },
    events: { title: "Le classement commence !", body: (_, x) => `Le classement Danmaku Swipe de ${FR_MONTHS[Number(x) - 1] ?? ""} commence ! Participe maintenant` },
  },
  de: {
    likes: { title: "Neues Like", body: (n) => `Jemandem gefällt „${n}“` },
    comments: { title: "Neuer Kommentar", body: (n, x) => `Neuer Kommentar zu „${n}“: ${x}` },
    plays: { title: "Deine Stage ist beliebt", body: (n, x) => `„${n}“ wurde ${x}-mal gespielt` },
    rewards: { title: "Eine Belohnung ist da!", body: (_, x) => (x === "monthly" ? "Deine Belohnung fürs Monatsranking ist da" : "Dein Freund hat gespielt! Deine Belohnung wartet") },
    events: { title: "Das Ranking hat begonnen!", body: (_, x) => `Das Swipe-Danmaku-Ranking im ${DE_MONTHS[Number(x) - 1] ?? ""} hat begonnen! Jetzt mitmachen` },
  },
  "pt-BR": {
    likes: { title: "Nova curtida", body: (n) => `Alguém curtiu "${n}"` },
    comments: { title: "Novo comentário", body: (n, x) => `Novo comentário em "${n}": ${x}` },
    plays: { title: "Sua fase está popular", body: (n, x) => `"${n}" foi jogada ${x} vezes` },
    rewards: { title: "Uma recompensa chegou!", body: (_, x) => (x === "monthly" ? "Sua recompensa do ranking mensal chegou" : "Seu amigo jogou! Sua recompensa está esperando") },
    events: { title: "O ranking começou!", body: (_, x) => `O ranking de Danmaku Swipe de ${PT_MONTHS[Number(x) - 1] ?? ""} começou! Participe agora` },
  },
  ru: {
    likes: { title: "Новый лайк", body: (n) => `Кому-то понравился «${n}»` },
    comments: { title: "Новый комментарий", body: (n, x) => `Новый комментарий к «${n}»: ${x}` },
    plays: { title: "Ваш уровень популярен", body: (n, x) => `«${n}» сыграли ${x} раз` },
    rewards: { title: "Пришла награда!", body: (_, x) => (x === "monthly" ? "Награда за месячный рейтинг пришла" : "Ваш друг сыграл! Награда ждёт вас") },
    events: { title: "Рейтинг начался!", body: (_, x) => `Рейтинг Свайп-Данмаку за ${RU_MONTHS[Number(x) - 1] ?? ""} начался! Участвуйте` },
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

/** ごほうびが届いたことを知らせる(ともだち招待の報酬・月間ランキングの報酬)。失敗しても例外は投げない */
export async function notifyReward(db: Firestore, to: string, what: "invite" | "monthly"): Promise<number> {
  try {
    const devices = await db.collection(`users/${to}/pushDevices`).get();
    const targets = devices.docs.filter((d) => d.get("enabled") === true && d.get("rewards") !== false && typeof d.get("token") === "string");
    if (targets.length === 0) return 0;
    const res = await getMessaging().sendEach(targets.map((d) => {
      const { title, body } = pushText(d.get("lang"), "rewards", "", what);
      return { token: d.get("token") as string, notification: { title, body }, data: { kind: "rewards", what }, apns: { payload: { aps: { sound: "default" } } } };
    }));
    await Promise.all(res.responses.map(async (r, i) => {
      const code = r.error?.code ?? "";
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token" || code === "messaging/invalid-argument") await targets[i].ref.delete();
    }));
    return res.successCount;
  } catch (err) {
    logger.warn("notify-reward-failed", { to, what, error: String(err) });
    return 0;
  }
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

/** 東京の時刻での、月(1〜12) */
export function tokyoMonth(now: number): number {
  return new Date(now + 9 * 3600 * 1000).getUTCMonth() + 1;
}

/**
 * お知らせ(events)をオンにしている全端末に、月のランキング戦の開始を知らせる。
 * 500件ずつ読んで送る(多くても止まらないように)。送れた数を返す
 */
export async function notifyMonthlyEvent(db: Firestore, now = Date.now(), pageSize = 500): Promise<number> {
  const month = String(tokyoMonth(now));
  let sent = 0;
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = db.collectionGroup("pushDevices").where("events", "==", true).orderBy("__name__").limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    last = snap.docs[snap.docs.length - 1];
    const targets = snap.docs.filter((d) => d.get("enabled") === true && typeof d.get("token") === "string");
    if (targets.length > 0) {
      try {
        const res = await getMessaging().sendEach(targets.map((d) => {
          const { title, body } = pushText(d.get("lang"), "events", "", month);
          return { token: d.get("token") as string, notification: { title, body }, data: { kind: "events", what: "swipeMonthly" }, apns: { payload: { aps: { sound: "default" } } } };
        }));
        sent += res.successCount;
        await Promise.all(res.responses.map(async (r, i) => {
          const code = r.error?.code ?? "";
          if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token" || code === "messaging/invalid-argument") await targets[i].ref.delete();
        }));
      } catch (err) {
        logger.warn("notify-event-failed", { error: String(err) });
      }
    }
    if (snap.size < pageSize) break;
  }
  logger.info("notify-event-sent", { month, sent });
  return sent;
}
