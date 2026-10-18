/** 英語の NG ワード。単語境界つきで判定する（"class" の "ass" などの誤検知を避ける） */
export const NG_EN_WORDS: string[] = [
  "fuck", "fucking", "shit", "bitch", "cunt", "whore", "slut", "dick", "cock", "pussy", "asshole",
  "nigger", "nigga", "faggot", "fag", "retard", "tranny", "chink", "spic",
  "rape", "rapist", "porn", "porno", "nazi", "hitler", "kys", "suicide", "molest",
];

/** 単語境界なしの部分一致でも判定する、十分に長く誤検知の少ないもの */
export const NG_EN_SUBSTRINGS: string[] = ["fuck", "nigger", "faggot", "motherfucker", "http", "www."];
