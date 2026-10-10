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

    // MARK: - Lists with several items（打鍵を当てはめた結果と、キャレットの位置で確かめる）

    /// text の "|" をキャレットとして replacement を打ち、結果の文字列（キャレットを "|" で示す）を返す。
    /// 補助が介入しなければ、そのまま挿入した結果を返す
    private func type(_ replacement: String, into marked: String, assist: EditorAssist = EditorAssist()) -> String {
        let caret = (marked as NSString).range(of: "|").location
        let text = (marked as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
        let isBackspace = replacement.isEmpty
        let range = isBackspace ? NSRange(location: caret - 1, length: 1) : NSRange(location: caret, length: 0)
        let ns = text as NSString
        if let edit = assist.intercept(text: text, range: range, replacement: replacement) {
            let result = ns.replacingCharacters(in: edit.range, with: edit.replacement) as NSString
            return result.replacingCharacters(in: NSRange(location: edit.selection.location, length: 0), with: "|")
        }
        let result = ns.replacingCharacters(in: range, with: replacement) as NSString
        return result.replacingCharacters(in: NSRange(location: range.location + (replacement as NSString).length, length: 0), with: "|")
    }

    func testOrderedListNewlinePutsCaretOnTheNewItem() {
        XCTAssertEqual(type("\n", into: "1. a|\n2. b\n3. c"), "1. a\n2. |\n3. b\n4. c")
    }

    func testOrderedListNewlineWithoutFollowingItemsPutsCaretOnTheNewItem() {
        XCTAssertEqual(type("\n", into: "1. a|"), "1. a\n2. |")
    }

    func testOrderedListRenumberingSkipsNestedChildren() {
        XCTAssertEqual(type("\n", into: "1. a|\n   - sub\n2. b\n3. c"), "1. a\n2. |\n   - sub\n3. b\n4. c")
    }

    func testOrderedListRenumberingStopsAtBlankLine() {
        XCTAssertEqual(type("\n", into: "1. a|\n2. b\n\n1. other"), "1. a\n2. |\n3. b\n\n1. other")
    }

    func testNewlineAtLineStartOfListItemIsPlainNewline() {
        XCTAssertEqual(type("\n", into: "- a\n|- b\n- c"), "- a\n\n|- b\n- c")
    }

    func testNewlineInsideIndentationOfListItemIsPlainNewline() {
        XCTAssertEqual(type("\n", into: "- a\n  |- b"), "- a\n  \n|- b")
    }

    func testNewlineOnEmptyNestedItemOutdentsOneLevel() {
        XCTAssertEqual(type("\n", into: "- a\n  - |"), "- a\n- |")
    }

    func testNewlineOnEmptyNestedOrderedItemOutdentsOneLevel() {
        XCTAssertEqual(type("\n", into: "1. a\n    1. |"), "1. a\n1. |")
    }

    func testNewlineOnEmptyTopLevelItemStillExitsList() {
        XCTAssertEqual(type("\n", into: "- a\n- |"), "- a\n|")
    }

    func testBackspaceRightAfterBulletRemovesMarker() {
        XCTAssertEqual(type("", into: "- a\n- |"), "- a\n|")
    }

    func testBackspaceRightAfterBulletKeepsText() {
        XCTAssertEqual(type("", into: "- |abc"), "|abc")
    }

    func testBackspaceRightAfterNestedBulletKeepsIndentation() {
        XCTAssertEqual(type("", into: "- a\n  - |"), "- a\n  |")
    }

    func testBackspaceRightAfterTaskMarkerRemovesWholeMarker() {
        XCTAssertEqual(type("", into: "- [ ] |"), "|")
    }

    func testBackspaceRightAfterOrderedMarkerRemovesMarker() {
        XCTAssertEqual(type("", into: "1. |"), "|")
    }

    func testBackspaceInsideItemTextIsNormal() {
        XCTAssertEqual(type("", into: "- ab|"), "- a|")
    }

    /// ``` と打てば ``` になる（4 つにならない）
    func testTypingCodeFenceGivesThreeBackticks() {
        var text = "|"
        for _ in 0..<3 { text = type("`", into: text) }
        XCTAssertEqual(text, "```|")
    }

    func testTypingEmptyStringQuotesGivesTwoQuotes() {
        var text = "|"
        for _ in 0..<2 { text = type("\"", into: text) }
        XCTAssertEqual(text, "\"\"|")
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

    /// 普通のエディタと同じく、後ろに文字が続く位置では閉じ括弧を足さない（"abc" の前で ( → "(abc"）
    func testParenNotPairedBeforeWord() {
        let a = EditorAssist()
        let edit = a.intercept(text: "abc", range: NSRange(location: 0, length: 0), replacement: "(")
        XCTAssertNil(edit)
    }

    func testParenNotPairedBeforeJapanese() {
        let a = EditorAssist()
        let edit = a.intercept(text: "日本語", range: NSRange(location: 0, length: 0), replacement: "[")
        XCTAssertNil(edit)
    }

    func testParenPairedBeforeSpace() {
        let a = EditorAssist()
        let edit = a.intercept(text: "a b", range: NSRange(location: 1, length: 0), replacement: "(")
        XCTAssertEqual(edit?.replacement, "()")
    }

    func testParenPairedBeforeCloser() {
        let a = EditorAssist()
        let edit = a.intercept(text: "[]", range: NSRange(location: 1, length: 0), replacement: "(")
        XCTAssertEqual(edit?.replacement, "()")
    }

    func testDoubleQuoteNotPairedAfterWord() {
        let a = EditorAssist()
        let edit = a.intercept(text: "5", range: NSRange(location: 1, length: 0), replacement: "\"")
        XCTAssertNil(edit)
    }

    func testBacktickNotPairedAfterWord() {
        let a = EditorAssist()
        let edit = a.intercept(text: "foo", range: NSRange(location: 3, length: 0), replacement: "`")
        XCTAssertNil(edit)
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
