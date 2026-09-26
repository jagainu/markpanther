import XCTest
@testable import MarkPantherCore

private func nsRange(_ text: String, _ substringMarker: String) -> NSRange {
    let r = text.range(of: substringMarker)!
    return NSRange(r, in: text)
}

final class MarkdownHighlighterTests: XCTestCase {

    // MARK: - Headings

    func testATXHeadingLevels() {
        let h = MarkdownHighlighter()
        for level in 1...6 {
            let hashes = String(repeating: "#", count: level)
            let text = "\(hashes) Title"
            let spans = h.highlight(text)
            XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: (text as NSString).length), style: .heading(level: level))), "level \(level) failed")
        }
    }

    func testATXHeadingHasMarkupSpanForHashes() {
        let h = MarkdownHighlighter()
        let text = "## Title"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 3), style: .markup)))
    }

    func testSetextHeadingLevel1() {
        let h = MarkdownHighlighter()
        let text = "Title\n====="
        let spans = h.highlight(text)
        let titleRange = nsRange(text, "Title")
        XCTAssertTrue(spans.contains(HighlightSpan(range: titleRange, style: .heading(level: 1))))
    }

    func testSetextHeadingLevel2() {
        let h = MarkdownHighlighter()
        let text = "Title\n-----"
        let spans = h.highlight(text)
        let titleRange = nsRange(text, "Title")
        XCTAssertTrue(spans.contains(HighlightSpan(range: titleRange, style: .heading(level: 2))))
    }

    // MARK: - Horizontal rule

    func testHorizontalRuleVariants() {
        let h = MarkdownHighlighter()
        for text in ["---", "***", "___", "- - -", "* * *"] {
            let spans = h.highlight(text)
            XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: (text as NSString).length), style: .horizontalRule)), "\(text) should be a horizontal rule")
        }
    }

    func testDashesAfterParagraphAreSetextNotHorizontalRule() {
        let h = MarkdownHighlighter()
        let text = "Some text\n---"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains(HighlightSpan(range: NSRange(location: 10, length: 3), style: .horizontalRule)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 9), style: .heading(level: 2))))
    }

    // MARK: - Inline styles

    func testStrongAndEmphasisTogetherDoNotMisfire() {
        let h = MarkdownHighlighter()
        let text = "**bold** and *italic*"
        let spans = h.highlight(text)
        let boldRange = nsRange(text, "**bold**")
        let italicRange = nsRange(text, "*italic*")
        XCTAssertTrue(spans.contains(HighlightSpan(range: boldRange, style: .strong)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: italicRange, style: .emphasis)))
        // Ensure no spurious single-* emphasis span was created out of the strong markers.
        XCTAssertFalse(spans.contains { $0.style == .emphasis && $0.range != italicRange })
    }

    func testStrikethroughAndHighlight() {
        let h = MarkdownHighlighter()
        let text = "~~gone~~ and ==marked=="
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "~~gone~~"), style: .strikethrough)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "==marked=="), style: .highlight)))
    }

    func testInlineCodeProtectsContentsFromOtherStyles() {
        let h = MarkdownHighlighter()
        let text = "`*not bold*`"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: (text as NSString).length), style: .inlineCode)))
        XCTAssertFalse(spans.contains { $0.style == .emphasis })
        XCTAssertFalse(spans.contains { $0.style == .strong })
    }

    // MARK: - Links / images / autolinks / bare URLs

    func testInlineLinkStylesTextAndURLSeparately() {
        let h = MarkdownHighlighter()
        let text = "see [my site](https://example.com) now"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "my site"), style: .link)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "https://example.com"), style: .linkURL)))
    }

    func testImageIsStyled() {
        let h = MarkdownHighlighter()
        let text = "![alt text](https://example.com/x.png)"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: (text as NSString).length), style: .image)))
    }

    func testAutolinkIsStyled() {
        let h = MarkdownHighlighter()
        let text = "go to <https://example.com> please"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "<https://example.com>"), style: .linkURL)))
    }

    func testBareURLIsStyled() {
        let h = MarkdownHighlighter()
        let text = "go to https://example.com please"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "https://example.com"), style: .linkURL)))
    }

    // MARK: - Blockquote / list markers

    func testBlockquoteMarkerStyled() {
        let h = MarkdownHighlighter()
        let text = "> quoted **text**"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 1), style: .blockquote)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "**text**"), style: .strong)))
    }

    func testUnorderedListMarkerStyled() {
        let h = MarkdownHighlighter()
        let text = "- item one"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 1), style: .listMarker)))
    }

    func testOrderedListMarkerStyled() {
        let h = MarkdownHighlighter()
        let text = "12. item"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 3), style: .listMarker)))
    }

    func testTaskListMarkerStyled() {
        let h = MarkdownHighlighter()
        let text = "- [x] done"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 1), style: .listMarker)))
        // Per the codeLanguage/taskMarker API contract, the checkbox part is
        // now its own .taskMarker style, split out from the bullet's .listMarker.
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "[x]"), style: .taskMarker)))
        XCTAssertFalse(spans.contains(HighlightSpan(range: nsRange(text, "[x]"), style: .listMarker)))
    }

    // MARK: - Fenced code blocks

    func testFencedCodeBlockStylesEveryLineAndSuppressesOtherStyles() {
        let h = MarkdownHighlighter()
        let text = "```\n**not bold**\n```"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .strong })
        // Every line, including fences, should be styled as codeBlock.
        let ns = text as NSString
        XCTAssertTrue(spans.contains { $0.style == .codeBlock && $0.range == NSRange(location: 0, length: 3) })
        let middleLineRange = nsRange(text, "**not bold**")
        XCTAssertTrue(spans.contains { $0.style == .codeBlock && $0.range == middleLineRange })
        XCTAssertTrue(spans.contains { $0.style == .codeBlock && $0.range == NSRange(location: ns.length - 3, length: 3) })
    }

    func testTildeFenceAlsoWorks() {
        let h = MarkdownHighlighter()
        let text = "~~~\ncode\n~~~"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains { $0.style == .codeBlock })
    }

    // MARK: - Frontmatter

    func testFrontmatterOnlyAtDocumentStart() {
        let h = MarkdownHighlighter()
        let text = "---\ntitle: Hi\n---\n# Body"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains { $0.style == .frontmatter && $0.range == NSRange(location: 0, length: 3) })
        XCTAssertTrue(spans.contains { $0.style == .frontmatter && $0.range == nsRange(text, "title: Hi") })
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "# Body"), style: .heading(level: 1))))
    }

    // MARK: - HTML comment

    func testHTMLCommentStyled() {
        let h = MarkdownHighlighter()
        let text = "before <!-- hidden **not bold** --> after"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "<!-- hidden **not bold** -->"), style: .htmlComment)))
        XCTAssertFalse(spans.contains { $0.style == .strong })
    }

    // MARK: - rangeToRehighlight

    func testRangeToRehighlightExpandsToParagraph() {
        let h = MarkdownHighlighter()
        let text = "one two three\nfour five six\nseven eight nine"
        let editedRange = nsRange(text, "five")
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertEqual(result, nsRange(text, "four five six\n"))
    }

    func testRangeToRehighlightReturnsFullTextWhenFenceInvolved() {
        let h = MarkdownHighlighter()
        let text = "para\n```\ncode\n```\nmore"
        let editedRange = nsRange(text, "```\ncode")
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertEqual(result, NSRange(location: 0, length: (text as NSString).length))
    }

    func testRangeToRehighlightReturnsFullTextWhenFrontmatterInvolved() {
        let h = MarkdownHighlighter()
        let text = "---\ntitle: x\n---\nbody"
        let editedRange = NSRange(location: 0, length: 3) // the opening "---"
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertEqual(result, NSRange(location: 0, length: (text as NSString).length))
    }

    // MARK: - rangeToRehighlight (new tokens)

    func testRangeToRehighlightReturnsFullTextForEditInsideOpenMathBlock() {
        let h = MarkdownHighlighter()
        let text = "$$\nx^2\ny^2\n$$"
        let editedRange = nsRange(text, "y^2")
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertEqual(result, NSRange(location: 0, length: (text as NSString).length))
    }

    func testRangeToRehighlightReturnsFullTextWhenSeparatorRowEdited() {
        let h = MarkdownHighlighter()
        let text = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let editedRange = nsRange(text, "---")
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertEqual(result, NSRange(location: 0, length: (text as NSString).length))
    }

    func testRangeToRehighlightReturnsFullTextWhenHeaderRowEdited() {
        let h = MarkdownHighlighter()
        let text = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let editedRange = nsRange(text, "A")
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertEqual(result, NSRange(location: 0, length: (text as NSString).length))
    }

    func testRangeToRehighlightStaysLocalForOrdinaryEdit() {
        let h = MarkdownHighlighter()
        let text = "one two three\nfour five six\nseven eight nine"
        let editedRange = nsRange(text, "five")
        let result = h.rangeToRehighlight(in: text, editedRange: editedRange)
        XCTAssertNotEqual(result, NSRange(location: 0, length: (text as NSString).length))
    }

    // MARK: - Ranged highlight

    func testRangedHighlightOnlyReturnsSpansInRange() {
        let h = MarkdownHighlighter()
        let text = "**one** **two** **three**"
        let range = nsRange(text, "**two**")
        let spans = h.highlight(text, in: range)
        XCTAssertTrue(spans.allSatisfy { NSIntersectionRange($0.range, range).length > 0 || $0.range.length == 0 })
        XCTAssertTrue(spans.contains { $0.style == .strong && $0.range == range })
        XCTAssertFalse(spans.contains { $0.range == nsRange(text, "**one**") })
    }

    func testRangedHighlightRespectsFenceStateFromDocumentStart() {
        let h = MarkdownHighlighter()
        let text = "```\n**not bold**\n```\n**bold**"
        let insideFenceRange = nsRange(text, "**not bold**")
        let spansInsideFence = h.highlight(text, in: insideFenceRange)
        XCTAssertFalse(spansInsideFence.contains { $0.style == .strong })

        let afterFenceRange = nsRange(text, "**bold**")
        let spansAfterFence = h.highlight(text, in: afterFenceRange)
        XCTAssertTrue(spansAfterFence.contains { $0.style == .strong })
    }

    // MARK: - Unicode

    func testHeadingWithEmojiKeepsCorrectRanges() {
        let h = MarkdownHighlighter()
        let text = "# 見出し😀テスト"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: (text as NSString).length), style: .heading(level: 1))))
    }

    // MARK: - Code fence / language

    func testCodeFenceLinesStyledSeparatelyFromCodeBlock() {
        let h = MarkdownHighlighter()
        let text = "```swift\nlet x = 1\n```"
        let spans = h.highlight(text)
        let openFenceLine = nsRange(text, "```swift")
        let closeFenceLine = NSRange(location: (text as NSString).length - 3, length: 3)
        XCTAssertTrue(spans.contains { $0.style == .codeFence && $0.range == openFenceLine })
        XCTAssertTrue(spans.contains { $0.style == .codeFence && $0.range == closeFenceLine })
        // The content line keeps its .codeBlock style, unaffected by codeFence.
        XCTAssertTrue(spans.contains { $0.style == .codeBlock && $0.range == nsRange(text, "let x = 1") })
        XCTAssertFalse(spans.contains { $0.style == .codeFence && $0.range == nsRange(text, "let x = 1") })
    }

    func testCodeLanguageStyledForInfoString() {
        let h = MarkdownHighlighter()
        let text = "```swift\ncode\n```"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "swift"), style: .codeLanguage)))
    }

    func testCodeLanguageAbsentWhenFenceHasNoInfoString() {
        let h = MarkdownHighlighter()
        let text = "```\ncode\n```"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .codeLanguage })
    }

    func testCodeLanguageAndFenceWithTildeFence() {
        let h = MarkdownHighlighter()
        let text = "~~~python\ncode\n~~~"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "python"), style: .codeLanguage)))
        XCTAssertTrue(spans.contains { $0.style == .codeFence && $0.range == nsRange(text, "~~~python") })
    }

    // MARK: - Tables

    func testTableHeaderAndMarkupStyled() {
        let h = MarkdownHighlighter()
        let text = "| Name | Age |\n| --- | --- |\n| Alice | 30 |"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "Name"), style: .tableHeader)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "Age"), style: .tableHeader)))
        // The delimiter row is styled as a whole.
        let sepLineRange = nsRange(text, "| --- | --- |")
        XCTAssertTrue(spans.contains(HighlightSpan(range: sepLineRange, style: .tableMarkup)))
        // Body row text is not tableHeader.
        XCTAssertFalse(spans.contains { $0.style == .tableHeader && $0.range == nsRange(text, "Alice") })
        // Every real "|" in the header and body rows (3 each) gets its own
        // tableMarkup span; the delimiter row's pipes are covered by the
        // single whole-line span asserted above instead.
        let markupPipeSpans = spans.filter { $0.style == .tableMarkup && $0.range.length == 1 }
        XCTAssertEqual(markupPipeSpans.count, 6)
    }

    func testTableCellWithEmojiAndJapaneseKeepsCorrectRanges() {
        let h = MarkdownHighlighter()
        let text = "| 名前😀 | 値 |\n| --- | --- |\n| 太郎 | 1 |"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "名前😀"), style: .tableHeader)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "値"), style: .tableHeader)))
    }

    func testTableCellPipeInsideInlineCodeIsNotASeparator() {
        let h = MarkdownHighlighter()
        let text = "| Cmd | Desc |\n| --- | --- |\n| `a\\|b` | pipe in code |"
        let spans = h.highlight(text)
        // The escaped pipe inside the inline-code cell must not be tableMarkup.
        let codeCellRange = nsRange(text, "`a\\|b`")
        XCTAssertFalse(spans.contains { $0.style == .tableMarkup && NSIntersectionRange($0.range, codeCellRange).length > 0 && $0.range.length == 1 })
        XCTAssertTrue(spans.contains { $0.style == .inlineCode && $0.range == codeCellRange })
    }

    func testOrdinaryPipeOutsideTableIsNotStyled() {
        let h = MarkdownHighlighter()
        let text = "just a | pipe in prose"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .tableMarkup })
        XCTAssertFalse(spans.contains { $0.style == .tableHeader })
    }

    func testRangedTableHighlightMatchesFullHighlight() {
        let h = MarkdownHighlighter()
        let text = "| Name | Age |\n| --- | --- |\n| Alice | 30 |"
        let headerRange = nsRange(text, "Name")
        let full = h.highlight(text)
        let ranged = h.highlight(text, in: headerRange)
        XCTAssertTrue(ranged.contains(HighlightSpan(range: headerRange, style: .tableHeader)))
        XCTAssertTrue(full.contains(HighlightSpan(range: headerRange, style: .tableHeader)))
    }

    // MARK: - HTML tags

    func testHTMLTagStyled() {
        let h = MarkdownHighlighter()
        let text = "before <div class=\"x\"> middle </div> after"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "<div class=\"x\">"), style: .htmlTag)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "</div>"), style: .htmlTag)))
    }

    func testSelfClosingHTMLTagStyled() {
        let h = MarkdownHighlighter()
        let text = "line one<br/>line two"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "<br/>"), style: .htmlTag)))
    }

    func testAutolinkIsNotHTMLTag() {
        let h = MarkdownHighlighter()
        let text = "go to <https://example.com> please"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .htmlTag })
        XCTAssertTrue(spans.contains { $0.style == .linkURL })
    }

    func testEmailAutolinkIsNotHTMLTag() {
        let h = MarkdownHighlighter()
        let text = "contact <user@example.com> now"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .htmlTag })
    }

    func testHTMLTagNotStyledInsideFencedCodeBlock() {
        let h = MarkdownHighlighter()
        let text = "```\n<div>not a tag here</div>\n```"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .htmlTag })
    }

    // MARK: - Footnotes

    func testFootnoteReferenceStyled() {
        let h = MarkdownHighlighter()
        let text = "See the note[^1] for details."
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "[^1]"), style: .footnote)))
    }

    func testFootnoteDefinitionLabelStyled() {
        let h = MarkdownHighlighter()
        let text = "[^1]: This is the note text."
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "[^1]:"), style: .footnote)))
        // Only one footnote span should cover the label (no duplicate from the
        // generic inline reference scan, which excludes labels followed by ":").
        let footnoteSpansAtStart = spans.filter { $0.style == .footnote && $0.range.location == 0 }
        XCTAssertEqual(footnoteSpansAtStart.count, 1)
    }

    // MARK: - Math

    func testInlineMathStyled() {
        let h = MarkdownHighlighter()
        let text = "energy is $E=mc^2$ famously"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "$E=mc^2$"), style: .math)))
    }

    func testMathProtectsContentsFromEmphasis() {
        let h = MarkdownHighlighter()
        let text = "$a*b*c$ is not emphasis"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "$a*b*c$"), style: .math)))
        XCTAssertFalse(spans.contains { $0.style == .emphasis })
    }

    func testCurrencyIsNotMisdetectedAsMath() {
        let h = MarkdownHighlighter()
        let text = "$5 and $10"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .math })
    }

    func testEscapedDollarIsNotMathDelimiter() {
        let h = MarkdownHighlighter()
        let text = "\\$5 is not math \\$ either"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .math })
    }

    func testBlockMathSingleLineStyled() {
        let h = MarkdownHighlighter()
        let text = "$$ x^2 + y^2 = z^2 $$"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: (text as NSString).length), style: .math)))
    }

    func testMultilineMathBlockStylesEveryLine() {
        let h = MarkdownHighlighter()
        let text = "$$\nx^2 + y^2\n= z^2\n$$"
        let spans = h.highlight(text)
        let ns = text as NSString
        XCTAssertTrue(spans.contains { $0.style == .math && $0.range == NSRange(location: 0, length: 2) })
        XCTAssertTrue(spans.contains { $0.style == .math && $0.range == nsRange(text, "x^2 + y^2") })
        XCTAssertTrue(spans.contains { $0.style == .math && $0.range == nsRange(text, "= z^2") })
        XCTAssertTrue(spans.contains { $0.style == .math && $0.range == NSRange(location: ns.length - 2, length: 2) })
    }

    func testMathNotStyledInsideInlineCode() {
        let h = MarkdownHighlighter()
        let text = "`$not math$`"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .math })
    }

    // MARK: - Task marker

    func testTaskMarkerUppercaseXStyled() {
        let h = MarkdownHighlighter()
        let text = "- [X] done"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: nsRange(text, "[X]"), style: .taskMarker)))
    }

    // MARK: - [TOC]

    func testTOCTokenStyled() {
        let h = MarkdownHighlighter()
        let text = "[TOC]"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 5), style: .tocToken)))
    }

    func testTOCLikeTextInParagraphIsNotToken() {
        let h = MarkdownHighlighter()
        let text = "please see [TOC] above for details"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .tocToken })
    }

    // MARK: - Hard break

    func testTrailingDoubleSpaceIsHardBreak() {
        let h = MarkdownHighlighter()
        let text = "line one  \nline two"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 8, length: 2), style: .hardBreak)))
    }

    func testTrailingBackslashIsHardBreak() {
        let h = MarkdownHighlighter()
        let text = "line one\\\nline two"
        let spans = h.highlight(text)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 8, length: 1), style: .hardBreak)))
    }

    func testSingleTrailingSpaceIsNotHardBreak() {
        let h = MarkdownHighlighter()
        let text = "line one \nline two"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .hardBreak })
    }

    // MARK: - Escape

    func testBackslashEscapedAsteriskIsNotEmphasis() {
        let h = MarkdownHighlighter()
        let text = "\\*not em\\*"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .emphasis })
        XCTAssertEqual(spans.filter { $0.style == .escape }.count, 2)
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 2), style: .escape)))
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 8, length: 2), style: .escape)))
    }

    func testEscapedHashIsNotHeadingMarkup() {
        let h = MarkdownHighlighter()
        let text = "\\# not a heading"
        let spans = h.highlight(text)
        XCTAssertFalse(spans.contains { $0.style == .heading(level: 1) })
        XCTAssertTrue(spans.contains(HighlightSpan(range: NSRange(location: 0, length: 2), style: .escape)))
    }

    // MARK: - Performance

    func testFullDocumentHighlightPerformance() {
        let h = MarkdownHighlighter()
        var lines: [String] = []
        for i in 0..<1400 {
            lines.append("- item \(i) with **bold** and *italic* and [link](https://example.com/\(i))")
        }
        let text = lines.joined(separator: "\n")
        XCTAssertGreaterThan((text as NSString).length, 100_000)

        // 壁時計ではなく CPU 時間で測る（マシンが混んでいるときに落ちないように）
        let start = clock()
        _ = h.highlight(text)
        let elapsed = Double(clock() - start) / Double(CLOCKS_PER_SEC)
        // 目的は計算量の劣化（二乗オーダー化など）の検知。Debug ビルド・高負荷時の揺れを見込んで枠は広めに取る
        XCTAssertLessThan(elapsed, 0.5, "Full highlight took \(elapsed)s of CPU time, expected < 0.5s")
    }
}
