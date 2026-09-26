import XCTest
@testable import MarkPantherCore

final class TextStatsTests: XCTestCase {
    func testEmpty() {
        let stats = TextStats(" \n")
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.approximateTokens, 0)
        XCTAssertEqual(stats.readingMinutes, 0)
    }

    func testEnglishWordsAndCharacters() {
        let stats = TextStats("The quick brown fox jumps over the lazy dog.")
        XCTAssertEqual(stats.words, 9)
        XCTAssertEqual(stats.characters, 44)
        // 英文はおおよそ 4 文字で 1 トークン
        XCTAssertEqual(stats.approximateTokens, 11)
        XCTAssertEqual(stats.readingMinutes, 1)
    }

    func testJapaneseCountsRoughlyOneTokenPerCharacter() {
        let text = String(repeating: "日本語の文章です。", count: 10)  // 90 文字
        let stats = TextStats(text)
        XCTAssertEqual(stats.characters, 90)
        XCTAssertEqual(stats.approximateTokens, 90)
    }

    func testMixedTextAddsBothParts() {
        let stats = TextStats("Claude が書いた README")  // ASCII 14 文字（空白含む）+ 和文 4 文字
        XCTAssertEqual(stats.approximateTokens, 4 + 4)
    }

    func testReadingTimeUsesWordsForEnglishAndCharactersForJapanese() {
        let english = TextStats(Array(repeating: "word", count: 460).joined(separator: " "))
        XCTAssertEqual(english.readingMinutes, 2)  // 230 wpm
        let japanese = TextStats(String(repeating: "あ", count: 1500))
        XCTAssertEqual(japanese.readingMinutes, 3)  // 500 文字/分
    }

    func testFormattedTokens() {
        XCTAssertEqual(TextStats.formatTokens(0), "0 tokens")
        XCTAssertEqual(TextStats.formatTokens(950), "~950 tokens")
        XCTAssertEqual(TextStats.formatTokens(1149), "~1.1K tokens")
        XCTAssertEqual(TextStats.formatTokens(25_400), "~25K tokens")
    }
}
