import XCTest
@testable import MarkPantherCore

final class EditorAssistTests: XCTestCase {

    // MARK: - Newline: list continuation

    func testNewlineContinuesUnorderedList() {
        let a = EditorAssist()
        let text = "- one"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n- ")
        XCTAssertEqual(edit?.selection, NSRange(location: range.location + 3, length: 0))
    }

    func testNewlineContinuesUnorderedListWithIndentation() {
        let a = EditorAssist()
        let text = "  * one"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n  * ")
    }

    func testNewlineExitsListWhenItemEmpty() {
        let a = EditorAssist()
        let text = "- one\n- "
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        // Should delete the empty "- " prefix instead of continuing the list.
        XCTAssertEqual(edit?.replacement, "")
        XCTAssertEqual(edit?.range, NSRange(location: 6, length: 2))
        XCTAssertEqual(edit?.selection, NSRange(location: 6, length: 0))
    }

    func testNewlineContinuesTaskListAsUnchecked() {
        let a = EditorAssist()
        let text = "- [x] done"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n- [ ] ")
    }

    func testNewlineContinuesOrderedListAndIncrements() {
        let a = EditorAssist()
        let text = "1. one"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n2. ")
    }

    func testNewlineOrderedListDoesNotIncrementWhenDisabled() {
        var a = EditorAssist()
        a.autoIncrementOrderedList = false
        let text = "1. one"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n1. ")
    }

    func testNewlineOrderedListRenumbersFollowingItems() {
        let a = EditorAssist()
        let text = "1. one\n2. two\n3. three"
        // Caret at end of "1. one" line.
        let range = NSRange(location: 6, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertNotNil(edit)
        // Reconstruct resulting text to check renumbering.
        let ns = text as NSString
        let result = ns.replacingCharacters(in: edit!.range, with: edit!.replacement)
        XCTAssertEqual(result, "1. one\n2. \n3. two\n4. three")
    }

    func testNewlineContinuesBlockquote() {
        let a = EditorAssist()
        let text = "> quoted"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n> ")
    }

    func testNewlinePlainLineContinuesIndentationOnly() {
        let a = EditorAssist()
        let text = "    plain line"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n    ")
    }

    func testNewlinePlainLineNoIndentationReturnsNil() {
        let a = EditorAssist()
        let text = "plain line"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertNil(edit)
    }

    func testNewlineInsideFencedCodeBlockOnlyContinuesIndentation() {
        let a = EditorAssist()
        let text = "```\n- not a list\n"
        let fullRange = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: fullRange, replacement: "\n")
        // Inside a fence, "- " should NOT be treated as a list marker.
        XCTAssertNil(edit)
    }

    func testNewlineDisabledWhenAutoInsertLinePrefixFalse() {
        var a = EditorAssist()
        a.autoInsertLinePrefix = false
        let text = "- one"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertNil(edit)
    }

    func testNewlineWithNonEmptySelectionReturnsNil() {
        let a = EditorAssist()
        let text = "- one"
        let range = NSRange(location: 2, length: 1) // "o" selected
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertNil(edit)
    }

    // MARK: - Bracket completion

    func testParenInsertsPairAtCaret() {
        let a = EditorAssist()
        let text = "foo "
        let range = NSRange(location: 4, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "(")
        XCTAssertEqual(edit?.replacement, "()")
        XCTAssertEqual(edit?.selection, NSRange(location: 5, length: 0))
    }

    func testBracketWrapsSelection() {
        let a = EditorAssist()
        let text = "foo bar"
        let range = NSRange(location: 4, length: 3) // "bar"
        let edit = a.intercept(text: text, range: range, replacement: "[")
        XCTAssertEqual(edit?.replacement, "[bar]")
        XCTAssertEqual(edit?.selection, NSRange(location: 5, length: 3))
    }

    func testQuoteOvertypesExistingClosingQuote() {
        let a = EditorAssist()
        let text = "\"foo\""
        let range = NSRange(location: 4, length: 0) // caret right before the closing quote
        let edit = a.intercept(text: text, range: range, replacement: "\"")
        XCTAssertEqual(edit?.range, NSRange(location: 4, length: 1))
        XCTAssertEqual(edit?.replacement, "\"")
        XCTAssertEqual(edit?.selection, NSRange(location: 5, length: 0))
    }

    func testClosingParenOvertypesExistingCloser() {
        let a = EditorAssist()
        let text = "(foo)"
        let range = NSRange(location: 4, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: ")")
        XCTAssertEqual(edit?.range, NSRange(location: 4, length: 1))
        XCTAssertEqual(edit?.selection, NSRange(location: 5, length: 0))
    }

    func testClosingParenWithNoMatchDoesNothingSpecial() {
        let a = EditorAssist()
        let text = "(foo"
        let range = NSRange(location: 4, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: ")")
        XCTAssertNil(edit)
    }

    func testApostropheNotCompletedMidWord() {
        let a = EditorAssist()
        let text = "dont"
        let range = NSRange(location: 4, length: 0) // "dont|"
        let edit = a.intercept(text: text, range: range, replacement: "'")
        XCTAssertNil(edit)
    }

    func testApostropheCompletedAtWordStart() {
        let a = EditorAssist()
        let text = "say "
        let range = NSRange(location: 4, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "'")
        XCTAssertEqual(edit?.replacement, "''")
    }

    func testBackspaceDeletesEmptyBracketPair() {
        let a = EditorAssist()
        let text = "()"
        // Caret was at position 1 (between "(" and ")"); backspace removes the
        // preceding character, i.e. the range (0, 1) covering "(".
        let range = NSRange(location: 0, length: 1)
        let edit = a.intercept(text: text, range: range, replacement: "")
        XCTAssertEqual(edit?.range, NSRange(location: 0, length: 2))
        XCTAssertEqual(edit?.replacement, "")
        XCTAssertEqual(edit?.selection, NSRange(location: 0, length: 0))
    }

    func testBackspaceDeletesEmptyStrongMarkerPair() {
        let a = EditorAssist()
        let text = "****"
        let range = NSRange(location: 1, length: 1) // backspace removing 1 char before caret at position 2
        let edit = a.intercept(text: text, range: range, replacement: "")
        XCTAssertEqual(edit?.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(edit?.replacement, "")
        XCTAssertEqual(edit?.selection, NSRange(location: 0, length: 0))
    }

    func testBracketCompletionDisabled() {
        var a = EditorAssist()
        a.autoCompleteBrackets = false
        let text = "foo "
        let range = NSRange(location: 4, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "(")
        XCTAssertNil(edit)
    }

    // MARK: - Tab

    func testTabInsertsSpacesToNextTabStop() {
        let a = EditorAssist()
        let text = "ab"
        let range = NSRange(location: 2, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\t")
        XCTAssertEqual(edit?.replacement, "  ") // tabWidth 4, column 2 -> 2 spaces to reach column 4
        XCTAssertEqual(edit?.range, range)
    }

    func testTabAtColumnZeroInsertsFullWidth() {
        let a = EditorAssist()
        let text = ""
        let range = NSRange(location: 0, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\t")
        XCTAssertEqual(edit?.replacement, "    ")
    }

    func testTabReturnsNilWhenInsertSpacesForTabDisabled() {
        var a = EditorAssist()
        a.insertSpacesForTab = false
        let text = "ab"
        let range = NSRange(location: 2, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\t")
        XCTAssertNil(edit)
    }

    func testTabIndentsListLineNearPrefix() {
        let a = EditorAssist()
        let text = "- one"
        let range = NSRange(location: 0, length: 0) // caret at very start, within prefix zone
        let edit = a.intercept(text: text, range: range, replacement: "\t")
        XCTAssertEqual(edit?.replacement, "    - one")
    }

    func testTabIndentsMultiLineSelection() {
        let a = EditorAssist()
        let text = "one\ntwo"
        let range = NSRange(location: 0, length: (text as NSString).length)
        let edit = a.intercept(text: text, range: range, replacement: "\t")
        let ns = text as NSString
        let result = ns.replacingCharacters(in: edit!.range, with: edit!.replacement)
        XCTAssertEqual(result, "    one\n    two")
    }

    // MARK: - Unicode

    func testNewlineListContinuationWithJapaneseContent() {
        let a = EditorAssist()
        let text = "- 日本語😀"
        let range = NSRange(location: (text as NSString).length, length: 0)
        let edit = a.intercept(text: text, range: range, replacement: "\n")
        XCTAssertEqual(edit?.replacement, "\n- ")
    }

    func testBracketWrapWithSurrogatePairSelection() {
        let a = EditorAssist()
        let text = "😀"
        let range = NSRange(location: 0, length: 2) // full emoji, 2 UTF-16 units
        let edit = a.intercept(text: text, range: range, replacement: "(")
        XCTAssertEqual(edit?.replacement, "(😀)")
        XCTAssertEqual(edit?.selection, NSRange(location: 1, length: 2))
    }
}
