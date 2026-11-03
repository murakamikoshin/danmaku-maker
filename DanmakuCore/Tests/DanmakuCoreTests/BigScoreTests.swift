import XCTest
@testable import DanmakuCore

/// スワイプ弾幕の上限なしの点数（仕様書 9 章）。正解の値は Python の整数で計算したもの
final class BigScoreTests: XCTestCase {
    private func big(_ s: String) -> BigScore { BigScore(s)! }

    // MARK: 計算

    func testConversionsRoundTrip() {
        XCTAssertEqual(BigScore.zero.description, "0")
        XCTAssertEqual(BigScore(0).description, "0")
        XCTAssertEqual(BigScore(UInt64.max).description, "18446744073709551615")
        XCTAssertEqual(BigScore(999_999_999).description, "999999999")
        XCTAssertEqual(BigScore(1_000_000_000).description, "1000000000", "区切りの境目")
        XCTAssertEqual(BigScore(-5).description, "0", "マイナスは 0")
        for s in ["1", "1000000000", "100000000000000000000", "515377520732011331036461129765621272702107522001"] {
            XCTAssertEqual(big(s).description, s)
        }
        XCTAssertEqual(big("000123").description, "123", "先頭の 0 は消える")
        XCTAssertEqual(big("000").description, "0")
        XCTAssertNil(BigScore(""))
        XCTAssertNil(BigScore("12a4"))
        XCTAssertNil(BigScore("-1"))
        XCTAssertNil(BigScore("1.5"))
    }

    func testPowersMatchPython() {
        XCTAssertEqual(BigScore.power(3, 0).description, "1")
        XCTAssertEqual(BigScore.power(3, 100).description, "515377520732011331036461129765621272702107522001")
        XCTAssertEqual(BigScore.power(2, 200).description, "1606938044258990275541962092341162602522202993782792835301376")
        XCTAssertEqual(BigScore.power(7, 77).description, "118181386580595879976868414312001964434038548836769923458287039207")
        XCTAssertEqual(BigScore.power(2, 64).description, "18446744073709551616", "UInt64 を 1 つ超える")
    }

    func testAddMultiplyDivideMatchPython() {
        let a = BigScore.power(3, 60) * big("100000000000000000000") + BigScore(12345)
        let b = BigScore.power(2, 70) + BigScore(999)
        XCTAssertEqual((a + b).description, "4239115827521620351429443321280591620717411316768")
        XCTAssertEqual((a * b).description, "5004664625222579971141526544528618166921684949376703557756442553101935")
        XCTAssertEqual((a * UInt32(1_000_000_007)).description, "4239115857195431144080785780106103240700000012345000086415")
        let (q8, r8) = a.quotientAndRemainder(dividingBy: 8)
        XCTAssertEqual(q8.description, "529889478440202543928680415012500000000000001543")
        XCTAssertEqual(r8, 1)
        XCTAssertEqual(a.divided(by: 2).description, "2119557913760810175714721660050000000000000006172")
        let (qb, rb) = b.quotientAndRemainder(dividingBy: 1_000_000_000)
        XCTAssertEqual(qb.description, "1180591620717")
        XCTAssertEqual(rb, 411_304_423)
        XCTAssertEqual(BigScore.zero.divided(by: 7), .zero)
        XCTAssertEqual(BigScore(7) * BigScore.zero, .zero)
        XCTAssertEqual(BigScore.zero + BigScore.zero, .zero)
    }

    func testCarriesAcrossLimbs() {
        XCTAssertEqual((BigScore(999_999_999) + BigScore(1)).description, "1000000000")
        XCTAssertEqual((big("999999999999999999") + BigScore(1)).description, "1000000000000000000")
        XCTAssertEqual((big("999999999999999999") * big("999999999999999999")).description, "999999999999999998000000000000000001")
    }

    func testComparison() {
        XCTAssertTrue(BigScore(5) < BigScore(6))
        XCTAssertFalse(BigScore(6) < BigScore(6))
        XCTAssertTrue(big("999999999") < big("1000000000"), "桁数（区切りの数）が違う")
        XCTAssertTrue(big("1000000001") > big("1000000000"))
        XCTAssertTrue(BigScore.power(3, 100) > BigScore.power(2, 150))
        XCTAssertEqual(BigScore.power(3, 4), BigScore(81))
        XCTAssertEqual(Set([BigScore(5), BigScore(5), BigScore(6)]).count, 2)
    }

    func testCodableUsesDecimalString() throws {
        let v = BigScore.power(3, 100)
        let data = try JSONEncoder().encode(["score": v])
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"score\":\"515377520732011331036461129765621272702107522001\"}")
        XCTAssertEqual(try JSONDecoder().decode([String: BigScore].self, from: data)["score"], v)
        XCTAssertThrowsError(try JSONDecoder().decode([String: BigScore].self, from: Data("{\"score\":\"abc\"}".utf8)))
    }

    func testRankingKeySortsLikeNumbers() {
        XCTAssertEqual(BigScore(7).rankingKey, "0017")
        XCTAssertEqual(big("16532314134240000").rankingKey, "01716532314134240000", "仕様書 15.3 章の例")
        let values = ["0", "9", "10", "99", "100", "999999999", "1000000000", "123456789012345678901234567890", "999999999999999999999999999999",
                      BigScore.power(3, 100).description, BigScore.power(2, 400).description]
        let keys = values.map { big($0).rankingKey }
        XCTAssertEqual(keys, keys.sorted(), "文字列として並べても数の大きさの順になる")
        XCTAssertEqual(values.map { big($0) }, values.map { big($0) }.sorted())
    }

    // MARK: 表示（仕様書 9 章の表と 5.1 章の例）

    func testJapaneseFormat() {
        let cases: [(String, String, String)] = [
            ("0", "0", "0"),
            ("9999", "9999", "9999"),
            ("10000", "1万", "1万"),
            ("1653231413424424", "1653兆2314億1342万4424", "1653兆"),
            ("16532314134240000", "1京6532兆3141億3424万", "1.65京"),
            ("100000005", "1億5", "1億"),
            ("45000000", "4500万", "4500万"),
            ("450000000", "4億5000万", "4.5億"),
        ]
        for (n, full, short) in cases {
            XCTAssertEqual(ScoreFormat.full(big(n), .japanese), full, n)
            XCTAssertEqual(ScoreFormat.short(big(n), .japanese), short, n)
        }
        let muryo = BigScore.power(10, 68)
        XCTAssertEqual(ScoreFormat.full(muryo, .japanese), "1無量大数")
        XCTAssertEqual(ScoreFormat.short(muryo, .japanese), "1無量大数")
        let a = BigScore(12345) * muryo + BigScore(7)
        XCTAssertEqual(ScoreFormat.full(a, .japanese), "1万2345無量大数7")
        XCTAssertEqual(ScoreFormat.short(a, .japanese), "1.23万無量大数")
        let b = BigScore.power(10, 80) + BigScore.power(10, 8)
        XCTAssertEqual(ScoreFormat.full(b, .japanese), "1兆無量大数1億")
        XCTAssertEqual(ScoreFormat.short(b, .japanese), "1兆無量大数")
        let c = BigScore(3) * BigScore.power(10, 140)
        XCTAssertEqual(ScoreFormat.full(c, .japanese), "3万無量大数無量大数")
        XCTAssertEqual(ScoreFormat.short(c, .japanese), "3万無量大数無量大数")
    }

    func testJapaneseUnitsAreAtTheRightPlaces() {
        let names = ["万", "億", "兆", "京", "垓", "𥝱", "穣", "溝", "澗", "正", "載", "極", "恒河沙", "阿僧祇", "那由他", "不可思議", "無量大数"]
        for (i, name) in names.enumerated() {
            let n = BigScore.power(10, 4 * (i + 1))
            XCTAssertEqual(ScoreFormat.full(n, .japanese), "1" + name, "10^\(4 * (i + 1))")
            XCTAssertEqual(ScoreFormat.short(n, .japanese), "1" + name)
            let almost = BigScore.power(10, 4 * (i + 1)) + BigScore(1)
            XCTAssertEqual(ScoreFormat.full(almost, .japanese), "1" + name + "1", "一の位が残る")
        }
    }

    func testShortFormatTruncatesInsteadOfRounding() {
        XCTAssertEqual(ScoreFormat.short(big("19999"), .japanese), "1.99万", "1.9999 → 1.99（切り上げて 2 にしない）")
        XCTAssertEqual(ScoreFormat.short(big("199999"), .japanese), "19.9万")
        XCTAssertEqual(ScoreFormat.short(big("1999999"), .japanese), "199万")
        XCTAssertEqual(ScoreFormat.short(big("10500"), .japanese), "1.05万", "小数第 2 位が 5 で、第 1 位が 0")
        XCTAssertEqual(ScoreFormat.short(big("12000"), .japanese), "1.2万", "末尾の 0 は消す")
        XCTAssertEqual(ScoreFormat.short(big("100000"), .japanese), "10万")
        XCTAssertEqual(ScoreFormat.short(big("101000"), .japanese), "10.1万")
    }

    func testEnglishFormat() {
        let cases: [(String, String, String)] = [
            ("0", "0", "0"),
            ("999", "999", "999"),
            ("1234", "1,234", "1.23K"),
            ("1653231413424424", "1,653,231,413,424,424", "1.65Qa"),
            ("16532314134240000", "16,532,314,134,240,000", "16.5Qa"),
            ("1000000", "1,000,000", "1M"),
            ("1500000000", "1,500,000,000", "1.5B"),
        ]
        for (n, full, short) in cases {
            XCTAssertEqual(ScoreFormat.full(big(n), .english), full, n)
            XCTAssertEqual(ScoreFormat.short(big(n), .english), short, n)
        }
        XCTAssertEqual(ScoreFormat.short(BigScore(999) * BigScore.power(10, 33), .english), "999Dc")
        XCTAssertEqual(ScoreFormat.short(BigScore.power(10, 36), .english), "1e36")
        XCTAssertEqual(ScoreFormat.short(BigScore(3) * BigScore.power(10, 140), .english), "3e140")
        XCTAssertEqual(ScoreFormat.short(BigScore(12345) * BigScore.power(10, 68) + BigScore(7), .english), "1.23e72")
        XCTAssertEqual(ScoreFormat.full(BigScore.power(10, 36), .english).count, 37 + 12, "37 桁 + カンマ 12 個")
    }

    func testEnglishSuffixesAreAtTheRightPlaces() {
        let suffixes = ["K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
        for (i, s) in suffixes.enumerated() {
            XCTAssertEqual(ScoreFormat.short(BigScore.power(10, 3 * (i + 1)), .english), "1" + s, "10^\(3 * (i + 1))")
        }
    }
}
