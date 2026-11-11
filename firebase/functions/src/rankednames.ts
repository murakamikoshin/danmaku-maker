/**
 * ランク戦のボットに付ける名前(Koshin の判断で、人と同じように見せる。2026-11-11)。
 * 言語ごとに、アプリの名前として自然なものを並べる。実在の有名人の名前は使わない。
 */
const NAMES: Record<string, readonly string[]> = {
  ja: ["ゆうと", "さくら", "はると", "みお", "そうた", "ひなた", "りく", "あおい", "こはる", "れん", "つむぎ", "かいと", "ゆい", "たくみ", "めい", "しゅん", "なぎ", "ここな", "だいき", "ちひろ", "ken", "Yuki", "ねこまる", "だんまくマン", "よけ職人", "そら", "ミナト", "あかり", "ゆずき", "けいた"],
  en: ["Alex", "Sam", "Jordan", "Riley", "Mia", "Leo", "Ava", "Noah", "Zoe", "Eli", "Kai", "Luna", "Max", "Ivy", "Theo", "Nora", "Finn", "Ruby", "Jay", "Emma", "dodger", "pixelfox", "starling", "ace_k", "Milo", "Iris", "Owen", "Lily", "Ben", "Chloe"],
  ko: ["민준", "서연", "도윤", "하은", "지호", "수아", "예준", "지우", "시우", "하린", "준서", "서윤", "Jin", "탄막러", "Minho", "유나", "현우", "다은", "건우", "채원"],
  zh: ["小明", "阿杰", "小雨", "晨晨", "子轩", "欣怡", "浩然", "雨桐", "Leo", "小鹿", "一帆", "思琪", "宇航", "梓涵", "弹幕君", "阿飞", "佳怡", "天宇", "Momo", "小白"],
  es: ["Lucas", "Sofía", "Mateo", "Valentina", "Diego", "Camila", "Hugo", "Lucía", "Pablo", "Martina", "Leo", "Elena", "Iker", "Paula", "Dani", "Alba", "Nico", "Sara", "Álex", "Carla"],
  fr: ["Lucas", "Emma", "Hugo", "Léa", "Louis", "Chloé", "Jules", "Manon", "Tom", "Inès", "Nathan", "Camille", "Léo", "Zoé", "Théo", "Lina", "Max", "Jade", "Enzo", "Clara"],
  de: ["Lukas", "Mia", "Leon", "Emma", "Finn", "Hannah", "Paul", "Lena", "Jonas", "Lea", "Ben", "Anna", "Elias", "Marie", "Noah", "Sophie", "Felix", "Lina", "Max", "Ella"],
  pt: ["Lucas", "Ana", "Gabriel", "Júlia", "Pedro", "Beatriz", "Rafa", "Larissa", "Mateus", "Sofia", "Davi", "Laura", "Leo", "Bia", "Gui", "Manu", "Caio", "Isa", "Theo", "Lara"],
  ru: ["Артём", "Мария", "Иван", "Анна", "Максим", "София", "Дима", "Алиса", "Миша", "Ева", "Саша", "Полина", "Кирилл", "Вика", "Егор", "Даша", "Лёша", "Катя", "Никита", "Оля"],
};

/** 言語コード(ja, en, zh-Hans …)から、名前の一覧を選ぶ。無ければ英語 */
export function namesFor(lang: unknown): readonly string[] {
  const l = typeof lang === "string" ? lang.toLowerCase() : "";
  const key = l.startsWith("zh") ? "zh" : l.startsWith("pt") ? "pt" : l.slice(0, 2);
  return NAMES[key] ?? NAMES.en!;
}
