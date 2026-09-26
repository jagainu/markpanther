import XCTest
@testable import MarkPantherCore

final class MarkdownOutlineTests: XCTestCase {
    private func outline(_ text: String) -> [OutlineItem] { MarkdownOutline.parse(text) }

    func testATXHeadingsWithLevelsAndLines() {
        let items = outline("# One\n\ntext\n\n## Two\n### Three\n")
        XCTAssertEqual(items, [
            OutlineItem(level: 1, title: "One", line: 0),
            OutlineItem(level: 2, title: "Two", line: 4),
            OutlineItem(level: 3, title: "Three", line: 5),
        ])
    }

    func testRequiresSpaceAfterHashesAndMaxSixLevels() {
        XCTAssertEqual(outline("#NoSpace\n####### seven\n#\n"), [])
        XCTAssertEqual(outline("###### six"), [OutlineItem(level: 6, title: "six", line: 0)])
    }

    func testStripsClosingHashesAndInlineMarkup() {
        let items = outline("## **Bold** and `code` and [link](https://example.com) ##\n")
        XCTAssertEqual(items, [OutlineItem(level: 2, title: "Bold and code and link", line: 0)])
    }

    func testAllowsUpToThreeLeadingSpaces() {
        XCTAssertEqual(outline("   # Indented"), [OutlineItem(level: 1, title: "Indented", line: 0)])
        XCTAssertEqual(outline("    # Code block"), [])
    }

    func testSetextHeadings() {
        let items = outline("Title\n=====\n\nSub title\n---\n")
        XCTAssertEqual(items, [
            OutlineItem(level: 1, title: "Title", line: 0),
            OutlineItem(level: 2, title: "Sub title", line: 3),
        ])
    }

    func testHorizontalRuleAfterBlankLineIsNotSetext() {
        XCTAssertEqual(outline("para\n\n---\n"), [])
    }

    func testListItemFollowedByDashesIsNotSetext() {
        XCTAssertEqual(outline("- item\n---\n"), [])
    }

    func testIgnoresHeadingsInsideFencedCode() {
        let text = "# Real\n```sh\n# comment\n```\n~~~\n## also not\n~~~\n## After\n"
        XCTAssertEqual(outline(text), [
            OutlineItem(level: 1, title: "Real", line: 0),
            OutlineItem(level: 2, title: "After", line: 7),
        ])
    }

    func testUnclosedFenceSwallowsRest() {
        XCTAssertEqual(outline("# A\n```\n# B\n"), [OutlineItem(level: 1, title: "A", line: 0)])
    }

    func testSkipsFrontmatter() {
        let text = "---\ntitle: x\n# not a heading\n---\n# Heading\n"
        XCTAssertEqual(outline(text), [OutlineItem(level: 1, title: "Heading", line: 4)])
    }

    func testDashesOnFirstLineWithoutClosingIsNotFrontmatter() {
        XCTAssertEqual(outline("---\n# Heading\n"), [OutlineItem(level: 1, title: "Heading", line: 1)])
    }

    func testJapaneseEmojiAndCRLF() {
        let items = outline("# 見出し😀\r\n\r\n## 次の節\r\n")
        XCTAssertEqual(items, [
            OutlineItem(level: 1, title: "見出し😀", line: 0),
            OutlineItem(level: 2, title: "次の節", line: 2),
        ])
    }

    func testEmptyTitleIsSkipped() {
        XCTAssertEqual(outline("# \n## ##\n"), [])
    }

    func testFilterMatchesCaseInsensitivelyAndKeepsOrder() {
        let items = outline("# Alpha\n## Beta setup\n## Gamma\n### SETUP notes\n")
        XCTAssertEqual(MarkdownOutline.filter(items, query: "setup").map(\.title), ["Beta setup", "SETUP notes"])
        XCTAssertEqual(MarkdownOutline.filter(items, query: "  ").count, 4)
    }
}
