import { describe, expect, it } from "vitest";
import { awardsFor, competitionRanks, isTitleId, monthEndMs, monthIdJst, monthStartMs, previousMonthId, scoreTitlesFor } from "../src/titles.js";

const jst = (y: number, m: number, d: number, h = 0, mi = 0) => Date.UTC(y, m - 1, d, h - 9, mi);

describe("月(日本時間の毎月 1 日 0:00 区切り)", () => {
  it("年月の ID になる", () => {
    expect(monthIdJst(jst(2026, 11, 9))).toBe("2026-11");
    expect(monthIdJst(jst(2026, 1, 1))).toBe("2026-01");
    expect(monthIdJst(jst(2026, 12, 31, 23, 59))).toBe("2026-12");
  });
  it("月末 23:59 は前の月、1 日 0:00 から次の月(日本時間)", () => {
    expect(monthIdJst(jst(2026, 10, 31, 23, 59))).toBe("2026-10");
    expect(monthIdJst(jst(2026, 11, 1, 0, 0))).toBe("2026-11");
    // UTC では 10/31 15:00 でも、日本時間では 11/1 0:00
    expect(monthIdJst(Date.UTC(2026, 9, 31, 15, 0))).toBe("2026-11");
    expect(monthIdJst(Date.UTC(2026, 9, 31, 14, 59))).toBe("2026-10");
  });
  it("月の始まり・終わり・前の月(年またぎ・うるう年を含む)", () => {
    expect(monthStartMs("2026-11")).toBe(jst(2026, 11, 1));
    expect(monthEndMs("2026-11")).toBe(jst(2026, 12, 1));
    expect(monthEndMs("2026-12")).toBe(jst(2027, 1, 1));
    expect(monthEndMs("2028-02") - monthStartMs("2028-02")).toBe(29 * 86400_000);   // うるう年
    expect(previousMonthId("2026-11")).toBe("2026-10");
    expect(previousMonthId("2026-01")).toBe("2025-12");
    expect(() => monthStartMs("2026-13")).toThrow();
  });
});

describe("スコア達成の称号", () => {
  it("しきい値以上で取れて、低い順に返る", () => {
    expect(scoreTitlesFor(99_999_999n)).toEqual([]);
    expect(scoreTitlesFor(10n ** 8n)).toEqual(["score1"]);
    expect(scoreTitlesFor(10n ** 12n)).toEqual(["score1", "score2"]);
    expect(scoreTitlesFor(10n ** 18n)).toEqual(["score1", "score2", "score3"]);
    expect(scoreTitlesFor(10n ** 28n)).toEqual(["score1", "score2", "score3", "score4"]);
    expect(scoreTitlesFor(10n ** 80n).length).toBe(4);
  });
});

describe("月間の順位の報酬", () => {
  it("1〜3位は王冠、4〜10位はメダル、そのほかは上位%", () => {
    expect(awardsFor(1, 140)).toEqual({ kinds: ["rank1", "pct1"], crown: 1, medal: false });   // 140人の1% = 2人まで
    expect(awardsFor(2, 140)).toEqual({ kinds: ["rank2", "pct1"], crown: 2, medal: false });
    expect(awardsFor(3, 140)).toEqual({ kinds: ["rank3", "pct10"], crown: 3, medal: false });
    expect(awardsFor(10, 140)).toEqual({ kinds: ["top10", "pct10"], crown: 0, medal: true });   // 10% = 14人まで
    expect(awardsFor(14, 140)).toEqual({ kinds: ["pct10"], crown: 0, medal: false });
    expect(awardsFor(15, 140)).toEqual({ kinds: ["pct50"], crown: 0, medal: false });
    expect(awardsFor(70, 140)).toEqual({ kinds: ["pct50"], crown: 0, medal: false });
    expect(awardsFor(71, 140)).toEqual({ kinds: [], crown: 0, medal: false });
  });
  it("人数が少ない月は、1人でも上位1%に入る(切り上げ)。1人なら1位", () => {
    expect(awardsFor(1, 1)).toEqual({ kinds: ["rank1", "pct1"], crown: 1, medal: false });
    expect(awardsFor(2, 2)).toEqual({ kinds: ["rank2"], crown: 2, medal: false });   // 2人中2位は、上位10%(1人まで)には入らない
  });
  it("同点は同じ順位", () => {
    expect(competitionRanks(["c", "c", "b", "a", "a", "a", "0"])).toEqual([1, 1, 3, 4, 4, 4, 7]);
  });
});

describe("称号の ID", () => {
  it("定義済みのスコア達成と「種類:年月」だけ通る", () => {
    for (const ok of ["score1", "score4", "rank1:2026-11", "pct50:2025-01", "top10:2026-12"]) expect(isTitleId(ok)).toBe(true);
    for (const ng of ["score5", "rank1", "rank9:2026-11", "rank1:2026-13", "rank1:2026-00", "rank1:2026-W46", "../x", "", 3, null, undefined]) expect(isTitleId(ng)).toBe(false);
  });
});
