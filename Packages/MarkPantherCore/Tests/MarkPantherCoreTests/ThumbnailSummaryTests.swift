import XCTest
@testable import MarkPantherCore

final class ThumbnailSummaryTests: XCTestCase {
    private func summary(_ markdown: String, maxLines: Int = 12) -> ThumbnailSummary {
        ThumbnailSummary.make(from: markdown, maxLines: maxLines)
    }

    func testTheFirstHeadingBecomesTheTitle() {
        let result = summary("# 設計メモ\n\n本文です。")
        XCTAssertEqual(result.title, "設計メモ")
        XCTAssertEqual(result.lines, ["本文です。"])
    }

    func testASetextHeadingAlsoCountsAsATitle() {
        let result = summary("設計メモ\n====\n\n本文です。")
        XCTAssertEqual(result.title, "設計メモ")
        XCTAssertEqual(result.lines, ["本文です。"])
    }

    func testWithoutAHeadingTheFirstLineIsTheTitle() {
        let result = summary("ただの段落。\n次の行。")
        XCTAssertEqual(result.title, "ただの段落。")
        XCTAssertEqual(result.lines, ["次の行。"])
    }

    func testFrontMatterIsSkipped() {
        let result = summary("---\ntitle: hidden\ntags: [a, b]\n---\n\n# 本当の見出し\n\n本文。")
        XCTAssertEqual(result.title, "本当の見出し")
        XCTAssertEqual(result.lines, ["本文。"])
    }

    func testAThematicBreakIsNotMistakenForFrontMatter() {
        let result = summary("# 見出し\n\n---\n\n本文。")
        XCTAssertEqual(result.title, "見出し")
        XCTAssertEqual(result.lines, ["本文。"])
    }

    func testListMarkersAreStripped() {
        let result = summary("# T\n\n- 一つめ\n* 二つめ\n1. 三つめ\n- [ ] 四つめ")
        XCTAssertEqual(result.lines, ["一つめ", "二つめ", "三つめ", "四つめ"])
    }

    func testEmphasisAndCodeMarkersAreStripped() {
        let result = summary("# T\n\n**強い**のと `code` と _斜め_。")
        XCTAssertEqual(result.lines, ["強いのと code と 斜め。"])
    }

    func testLinksKeepTheirTextAndLoseTheURL() {
        let result = summary("# T\n\n[公式ドキュメント](https://example.com/a/b) を見る。")
        XCTAssertEqual(result.lines, ["公式ドキュメント を見る。"])
    }

    func testFencedCodeIsLeftOut() {
        let result = summary("# T\n\n前。\n\n```swift\nlet x = 1\n```\n\n後。")
        XCTAssertEqual(result.lines, ["前。", "後。"])
    }

    func testLaterHeadingsSurviveAsLinesWithoutTheirHashes() {
        let result = summary("# T\n\n本文。\n\n## 次の節\n\nその本文。")
        XCTAssertEqual(result.lines, ["本文。", "次の節", "その本文。"])
    }

    func testTableSeparatorRowsAreDropped() {
        let result = summary("# T\n\n| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(result.lines, ["| A | B |", "| 1 | 2 |"])
    }

    func testBlockQuoteMarkersAreStripped() {
        let result = summary("# T\n\n> 引用です。")
        XCTAssertEqual(result.lines, ["引用です。"])
    }

    func testRunsOfWhitespaceCollapse() {
        let result = summary("# T\n\n間隔   が    広い。")
        XCTAssertEqual(result.lines, ["間隔 が 広い。"])
    }

    func testTheLineCountIsCapped() {
        let body = (1...50).map { "行\($0)" }.joined(separator: "\n\n")
        XCTAssertEqual(summary("# T\n\n" + body, maxLines: 4).lines.count, 4)
    }

    func testAnEmptyDocumentHasNothingToShow() {
        let result = summary("   \n\n\n")
        XCTAssertNil(result.title)
        XCTAssertTrue(result.lines.isEmpty)
    }

    func testStopsReadingLongDocumentsEarly() {
        // 巨大なファイルでもサムネイル1枚のために全文を走らない
        let huge = "# T\n\n" + String(repeating: "本文の行。\n", count: 100_000)
        let result = summary(huge, maxLines: 8)
        XCTAssertEqual(result.lines.count, 8)
    }
}
