import XCTest
@testable import MarkPantherCore

private func nsRange(_ text: String, _ substringMarker: String) -> NSRange {
    // Finds the range of `substringMarker` in `text`, for convenience in tests.
    let r = text.range(of: substringMarker)!
    return NSRange(r, in: text)
}

private func caretRange(_ text: String, at index: Int) -> NSRange {
    NSRange(location: index, length: 0)
}

final class MarkdownFormatterTests: XCTestCase {

    // MARK: - Strong

    func testStrongWrapsEmptySelectionAtCaret() {
        let f = MarkdownFormatter()
        let text = "hello"
        let sel = caretRange(text, at: 5) // end of "hello"
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.range, NSRange(location: 5, length: 0))
        XCTAssertEqual(edit?.replacement, "****")
        XCTAssertEqual(edit?.selection, NSRange(location: 7, length: 0))
    }

    func testStrongRemovesEmptyPairAtCaret() {
        let f = MarkdownFormatter()
        let text = "****"
        let sel = caretRange(text, at: 2) // between ** and **
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(edit?.replacement, "")
        XCTAssertEqual(edit?.selection, NSRange(location: 0, length: 0))
    }

    func testStrongWrapsSelection() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.range, sel)
        XCTAssertEqual(edit?.replacement, "**world**")
        XCTAssertEqual(edit?.selection, NSRange(location: sel.location + 2, length: 5))
    }

    func testStrongUnwrapsInsideSelection() {
        let f = MarkdownFormatter()
        let text = "hello **world**"
        let sel = nsRange(text, "**world**")
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "world")
        XCTAssertEqual(edit?.selection, NSRange(location: sel.location, length: 5))
    }

    func testStrongUnwrapsOutsideSelection() {
        let f = MarkdownFormatter()
        let text = "hello **world**"
        let sel = nsRange(text, "world")
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.range, NSRange(location: sel.location - 2, length: 9))
        XCTAssertEqual(edit?.replacement, "world")
        XCTAssertEqual(edit?.selection, NSRange(location: sel.location - 2, length: 5))
    }

    // MARK: - Emphasis vs Strong disambiguation

    func testEmphasisWrapsSelectionWithSingleAsterisks() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let edit = f.apply(.emphasis, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "*world*")
    }

    func testEmphasisDoesNotMisfireInsideStrong() {
        let f = MarkdownFormatter()
        let text = "hello **world**"
        let sel = nsRange(text, "world")
        // selection is surrounded by "**" not a single "*", so emphasis should WRAP, not unwrap.
        let edit = f.apply(.emphasis, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "*world*")
    }

    func testEmphasisUnwrapsOutsideSingleAsterisk() {
        let f = MarkdownFormatter()
        let text = "hello *world*"
        let sel = nsRange(text, "world")
        let edit = f.apply(.emphasis, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "world")
        XCTAssertEqual(edit?.range, NSRange(location: sel.location - 1, length: 7))
    }

    func testStrongDoesNotMisfireOnSingleEmphasis() {
        let f = MarkdownFormatter()
        let text = "hello *world*"
        let sel = nsRange(text, "world")
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "**world**")
    }

    // MARK: - Underline / Strikethrough / Highlight / InlineCode / Comment

    func testUnderlineTogglesWithUnderscore() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let wrapped = f.apply(.underline, to: text, selection: sel)
        XCTAssertEqual(wrapped?.replacement, "_world_")

        let text2 = "hello _world_"
        let sel2 = nsRange(text2, "world")
        let unwrapped = f.apply(.underline, to: text2, selection: sel2)
        XCTAssertEqual(unwrapped?.replacement, "world")
    }

    func testStrikethroughToggles() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let wrapped = f.apply(.strikethrough, to: text, selection: sel)
        XCTAssertEqual(wrapped?.replacement, "~~world~~")

        let text2 = "hello ~~world~~"
        let sel2 = nsRange(text2, "~~world~~")
        let unwrapped = f.apply(.strikethrough, to: text2, selection: sel2)
        XCTAssertEqual(unwrapped?.replacement, "world")
    }

    func testHighlightToggles() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let wrapped = f.apply(.highlight, to: text, selection: sel)
        XCTAssertEqual(wrapped?.replacement, "==world==")
    }

    func testInlineCodeToggles() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let wrapped = f.apply(.inlineCode, to: text, selection: sel)
        XCTAssertEqual(wrapped?.replacement, "`world`")

        let text2 = "hello `world`"
        let sel2 = nsRange(text2, "world")
        let unwrapped = f.apply(.inlineCode, to: text2, selection: sel2)
        XCTAssertEqual(unwrapped?.replacement, "world")
    }

    func testCommentToggles() {
        let f = MarkdownFormatter()
        let text = "hello world"
        let sel = nsRange(text, "world")
        let wrapped = f.apply(.comment, to: text, selection: sel)
        XCTAssertEqual(wrapped?.replacement, "<!-- world -->")

        let text2 = "hello <!-- world -->"
        let sel2 = nsRange(text2, "world")
        let unwrapped = f.apply(.comment, to: text2, selection: sel2)
        XCTAssertEqual(unwrapped?.replacement, "world")
    }

    // MARK: - Link / Image

    func testLinkWrapsPlainSelectionAndSelectsURL() {
        let f = MarkdownFormatter()
        let text = "check this out"
        let sel = nsRange(text, "this")
        let edit = f.apply(.link, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "[this](url)")
        // "url" should be selected within the replacement.
        let replacement = edit!.replacement
        let urlRangeInReplacement = (replacement as NSString).range(of: "url")
        XCTAssertEqual(edit?.selection, NSRange(location: edit!.range.location + urlRangeInReplacement.location, length: 3))
    }

    func testLinkWithURLSelectedPlacesCaretInBrackets() {
        let f = MarkdownFormatter()
        let text = "see https://example.com here"
        let sel = nsRange(text, "https://example.com")
        let edit = f.apply(.link, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "[](https://example.com)")
        XCTAssertEqual(edit?.selection, NSRange(location: sel.location + 1, length: 0))
    }

    func testImageWrapsWithExclamation() {
        let f = MarkdownFormatter()
        let text = "check this out"
        let sel = nsRange(text, "this")
        let edit = f.apply(.image, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "![this](url)")
    }

    func testImageWithURLSelected() {
        let f = MarkdownFormatter()
        let text = "see https://example.com here"
        let sel = nsRange(text, "https://example.com")
        let edit = f.apply(.image, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "![](https://example.com)")
        XCTAssertEqual(edit?.selection, NSRange(location: sel.location + 2, length: 0))
    }

    // MARK: - Heading

    func testHeadingAddsPrefix() {
        let f = MarkdownFormatter()
        let text = "Title"
        let sel = NSRange(location: 0, length: 0)
        let edit = f.apply(.heading(2), to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "## Title")
    }

    func testHeadingRemovesSameLevel() {
        let f = MarkdownFormatter()
        let text = "## Title"
        let sel = NSRange(location: 0, length: 0)
        let edit = f.apply(.heading(2), to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "Title")
    }

    func testHeadingChangesLevel() {
        let f = MarkdownFormatter()
        let text = "## Title"
        let sel = NSRange(location: 0, length: 0)
        let edit = f.apply(.heading(3), to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "### Title")
    }

    func testHeadingMultiline() {
        let f = MarkdownFormatter()
        let text = "one\ntwo\nthree"
        let sel = NSRange(location: 0, length: (text as NSString).length) // full selection
        let edit = f.apply(.heading(1), to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "# one\n# two\n# three")
    }

    // MARK: - Lists

    func testUnorderedListAddsMarkerToEachLine() {
        let f = MarkdownFormatter()
        let text = "one\ntwo"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.unorderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "- one\n- two")
    }

    func testUnorderedListRemovesWhenAllLinesAlreadyMarked() {
        let f = MarkdownFormatter()
        let text = "- one\n- two"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.unorderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "one\ntwo")
    }

    func testUnorderedListConvertsFromOrdered() {
        let f = MarkdownFormatter()
        let text = "1. one\n2. two"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.unorderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "- one\n- two")
    }

    func testUnorderedListSkipsBlankLines() {
        let f = MarkdownFormatter()
        let text = "one\n\ntwo"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.unorderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "- one\n\n- two")
    }

    func testUnorderedListInsertsOnSingleBlankLineSelection() {
        let f = MarkdownFormatter()
        let text = ""
        let sel = NSRange(location: 0, length: 0)
        let edit = f.apply(.unorderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "- ")
    }

    func testOrderedListNumbersSequentiallySkippingBlanks() {
        let f = MarkdownFormatter()
        let text = "one\n\ntwo"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.orderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "1. one\n\n2. two")
    }

    func testOrderedListRemovesWhenAllLinesAlreadyMarked() {
        let f = MarkdownFormatter()
        let text = "1. one\n2. two"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.orderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "one\ntwo")
    }

    func testListMarkerConfigurable() {
        let f = MarkdownFormatter(listMarker: "*")
        let text = "one"
        let sel = NSRange(location: 0, length: 0)
        let edit = f.apply(.unorderedList, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "* one")
    }

    // MARK: - Blockquote

    func testBlockquoteAddsPrefix() {
        let f = MarkdownFormatter()
        let text = "one\ntwo"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.blockquote, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "> one\n> two")
    }

    func testBlockquoteRemovesWhenAllLinesAlreadyMarked() {
        let f = MarkdownFormatter()
        let text = "> one\n> two"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.blockquote, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "one\ntwo")
    }

    // MARK: - Shift left/right

    func testShiftRightIndentsAllLines() {
        let f = MarkdownFormatter()
        let text = "one\ntwo"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.shiftRight, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "    one\n    two")
    }

    func testShiftLeftRemovesIndentUnit() {
        let f = MarkdownFormatter()
        let text = "    one\n    two"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.shiftLeft, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "one\ntwo")
    }

    func testShiftLeftRemovesTab() {
        let f = MarkdownFormatter()
        let text = "\tone"
        let sel = NSRange(location: 0, length: 3)
        let edit = f.apply(.shiftLeft, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "one")
    }

    func testShiftLeftRemovesPartialLeadingWhitespace() {
        let f = MarkdownFormatter()
        let text = "  one" // only 2 spaces, less than indentUnit (4)
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.shiftLeft, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "one")
    }

    func testShiftLeftReturnsNilWhenNoIndentation() {
        let f = MarkdownFormatter()
        let text = "one\ntwo"
        let sel = NSRange(location: 0, length: (text as NSString).length)
        let edit = f.apply(.shiftLeft, to: text, selection: sel)
        XCTAssertNil(edit)
    }

    // MARK: - Unicode / UTF-16 correctness

    func testStrongWrapWithJapaneseAndEmoji() {
        let f = MarkdownFormatter()
        let text = "こんにちは😀世界"
        // Select "😀世界" — emoji is a surrogate pair in UTF-16.
        let sel = nsRange(text, "😀世界")
        let edit = f.apply(.strong, to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "**😀世界**")
        XCTAssertEqual(edit?.range, sel)
        // Selection should cover "😀世界" inside the markers.
        let ns = (text as NSString)
        let before = ns.substring(to: sel.location)
        XCTAssertEqual(before, "こんにちは")
    }

    func testHeadingWithJapaneseText() {
        let f = MarkdownFormatter()
        let text = "見出し😀"
        let sel = NSRange(location: 0, length: 0)
        let edit = f.apply(.heading(1), to: text, selection: sel)
        XCTAssertEqual(edit?.replacement, "# 見出し😀")
    }
}
