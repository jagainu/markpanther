import Foundation

/// Editing assists (list continuation, bracket completion, Tab handling)
/// expressed as a pure function over text + a proposed edit.
public struct EditorAssist: Sendable {
    public var autoCompleteBrackets: Bool
    public var autoInsertLinePrefix: Bool
    public var autoIncrementOrderedList: Bool
    public var insertSpacesForTab: Bool
    public var tabWidth: Int

    public init(
        autoCompleteBrackets: Bool = true,
        autoInsertLinePrefix: Bool = true,
        autoIncrementOrderedList: Bool = true,
        insertSpacesForTab: Bool = true,
        tabWidth: Int = 4
    ) {
        self.autoCompleteBrackets = autoCompleteBrackets
        self.autoInsertLinePrefix = autoInsertLinePrefix
        self.autoIncrementOrderedList = autoIncrementOrderedList
        self.insertSpacesForTab = insertSpacesForTab
        self.tabWidth = tabWidth
    }

    public init() {
        self.init(autoCompleteBrackets: true, autoInsertLinePrefix: true, autoIncrementOrderedList: true, insertSpacesForTab: true, tabWidth: 4)
    }

    public func intercept(text: String, range: NSRange, replacement: String) -> TextEdit? {
        let ns = text as NSString

        if replacement == "\n" && range.length == 0 {
            return interceptNewline(ns, at: range.location)
        }
        if replacement == "\t" {
            return interceptTab(ns, range: range)
        }
        if replacement.isEmpty && range.length == 1 {
            return interceptBackspacePairDeletion(ns, range: range)
        }
        if replacement.utf16.count == 1, let ch = replacement.first {
            return interceptBracket(ns, range: range, char: ch)
        }
        return nil
    }

    // MARK: - Newline / list continuation

    private static let taskRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]) \\[([ xX])\\] (.*)$")
    private static let unorderedRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]) (.*)$")
    private static let orderedRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d+)([.)]) (.*)$")
    private static let blockquoteRegex = try! NSRegularExpression(pattern: "^([ \\t]*)> (.*)$")
    private static let leadingWhitespaceRegex = try! NSRegularExpression(pattern: "^[ \\t]*")
    private static let fenceRegex = try! NSRegularExpression(pattern: "^[ \\t]*(```|~~~)")

    private func fullMatch(_ regex: NSRegularExpression, in string: String) -> NSTextCheckingResult? {
        let ns = string as NSString
        return regex.firstMatch(in: string, range: NSRange(location: 0, length: ns.length))
    }

    private func interceptNewline(_ ns: NSString, at location: Int) -> TextEdit? {
        guard autoInsertLinePrefix else { return nil }

        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let lineText = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))

        if isInsideFencedCodeBlock(ns, beforeLineStart: lineStart) {
            return continueIndentationOnly(lineText, at: location)
        }

        if let m = fullMatch(Self.taskRegex, in: lineText) {
            let indentation = substring(lineText, m, group: 1)
            let marker = substring(lineText, m, group: 2)
            let rest = substring(lineText, m, group: 4)
            if rest.isEmpty {
                return exitLine(ns, lineStart: lineStart, at: location)
            }
            let newPrefix = "\n\(indentation)\(marker) [ ] "
            return TextEdit(range: NSRange(location: location, length: 0), replacement: newPrefix, selection: NSRange(location: location + newPrefix.utf16.count, length: 0))
        }

        if let m = fullMatch(Self.orderedRegex, in: lineText) {
            let indentation = substring(lineText, m, group: 1)
            let numberText = substring(lineText, m, group: 2)
            let separator = substring(lineText, m, group: 3)
            let rest = substring(lineText, m, group: 4)
            if rest.isEmpty {
                return exitLine(ns, lineStart: lineStart, at: location)
            }
            let currentNumber = Int(numberText) ?? 1
            let newNumber = autoIncrementOrderedList ? currentNumber + 1 : currentNumber
            let newPrefix = "\n\(indentation)\(newNumber)\(separator) "
            let primaryEdit = (range: NSRange(location: location, length: 0), replacement: newPrefix)

            var edits: [(range: NSRange, replacement: String)] = [primaryEdit]
            if autoIncrementOrderedList {
                edits.append(contentsOf: renumberEdits(ns, afterLineEnd: lineEnd, indentation: indentation, startingAt: newNumber + 1))
            }
            return combineEdits(ns, edits: edits, caretAfterPrimary: location + newPrefix.utf16.count)
        }

        if let m = fullMatch(Self.unorderedRegex, in: lineText) {
            let indentation = substring(lineText, m, group: 1)
            let marker = substring(lineText, m, group: 2)
            let rest = substring(lineText, m, group: 3)
            if rest.isEmpty {
                return exitLine(ns, lineStart: lineStart, at: location)
            }
            let newPrefix = "\n\(indentation)\(marker) "
            return TextEdit(range: NSRange(location: location, length: 0), replacement: newPrefix, selection: NSRange(location: location + newPrefix.utf16.count, length: 0))
        }

        if let m = fullMatch(Self.blockquoteRegex, in: lineText) {
            let indentation = substring(lineText, m, group: 1)
            let rest = substring(lineText, m, group: 2)
            if rest.isEmpty {
                return exitLine(ns, lineStart: lineStart, at: location)
            }
            let newPrefix = "\n\(indentation)> "
            return TextEdit(range: NSRange(location: location, length: 0), replacement: newPrefix, selection: NSRange(location: location + newPrefix.utf16.count, length: 0))
        }

        return continueIndentationOnly(lineText, at: location)
    }

    private func continueIndentationOnly(_ lineText: String, at location: Int) -> TextEdit? {
        guard let m = fullMatch(Self.leadingWhitespaceRegex, in: lineText), m.range.length > 0 else {
            return nil
        }
        let indentation = substring(lineText, m, group: 0)
        let newPrefix = "\n\(indentation)"
        return TextEdit(range: NSRange(location: location, length: 0), replacement: newPrefix, selection: NSRange(location: location + newPrefix.utf16.count, length: 0))
    }

    /// The current line's content-after-prefix is empty: remove the prefix and
    /// exit the list/quote instead of inserting a new line.
    private func exitLine(_ ns: NSString, lineStart: Int, at location: Int) -> TextEdit {
        let range = NSRange(location: lineStart, length: location - lineStart)
        return TextEdit(range: range, replacement: "", selection: NSRange(location: lineStart, length: 0))
    }

    private func isInsideFencedCodeBlock(_ ns: NSString, beforeLineStart lineStart: Int) -> Bool {
        var inFence = false
        var location = 0
        while location < lineStart {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let text = ns.substring(with: NSRange(location: start, length: contentsEnd - start))
            if fullMatch(Self.fenceRegex, in: text) != nil {
                inFence.toggle()
            }
            if end <= location { break }
            location = end
        }
        return inFence
    }

    private func renumberEdits(_ ns: NSString, afterLineEnd: Int, indentation: String, startingAt firstNumber: Int) -> [(range: NSRange, replacement: String)] {
        var edits: [(range: NSRange, replacement: String)] = []
        var location = afterLineEnd
        var nextNumber = firstNumber
        let totalLength = ns.length
        while location < totalLength {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let lineText = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            guard let m = fullMatch(Self.orderedRegex, in: lineText) else { break }
            let lineIndentation = substring(lineText, m, group: 1)
            guard lineIndentation == indentation else { break }
            let numberRange = m.range(at: 2)
            let absoluteRange = NSRange(location: lineStart + numberRange.location, length: numberRange.length)
            edits.append((absoluteRange, String(nextNumber)))
            nextNumber += 1
            if lineEnd <= location { break }
            location = lineEnd
        }
        return edits
    }

    private func substring(_ text: String, _ match: NSTextCheckingResult, group: Int) -> String {
        let ns = text as NSString
        let r = match.range(at: group)
        guard r.location != NSNotFound else { return "" }
        return ns.substring(with: r)
    }

    /// Combines the primary insertion edit with any subsequent renumbering
    /// edits into a single `TextEdit`.
    private func combineEdits(_ ns: NSString, edits: [(range: NSRange, replacement: String)], caretAfterPrimary: Int) -> TextEdit? {
        guard !edits.isEmpty else { return nil }
        let sorted = edits.sorted { $0.range.location < $1.range.location }
        let spanStart = sorted.first!.range.location
        let spanEnd = sorted.last!.range.location + sorted.last!.range.length

        var result = ""
        var cursor = spanStart
        for edit in sorted {
            result += ns.substring(with: NSRange(location: cursor, length: edit.range.location - cursor))
            result += edit.replacement
            cursor = edit.range.location + edit.range.length
        }
        result += ns.substring(with: NSRange(location: cursor, length: spanEnd - cursor))

        func mapPosition(_ original: Int) -> Int {
            var delta = 0
            for edit in sorted {
                let editEnd = edit.range.location + edit.range.length
                if editEnd <= original {
                    delta += edit.replacement.utf16.count - edit.range.length
                } else if edit.range.location < original && original < editEnd {
                    return edit.range.location + delta
                } else {
                    break
                }
            }
            return original + delta
        }

        let caretMapped = mapPosition(caretAfterPrimary)
        return TextEdit(range: NSRange(location: spanStart, length: spanEnd - spanStart), replacement: result, selection: NSRange(location: caretMapped, length: 0))
    }

    // MARK: - Bracket completion

    private static let openerToCloser: [Character: Character] = ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
    private static let closerToOpener: [Character: Character] = [")": "(", "]": "[", "}": "{", "\"": "\"", "'": "'", "`": "`"]

    private func interceptBracket(_ ns: NSString, range: NSRange, char: Character) -> TextEdit? {
        guard autoCompleteBrackets else { return nil }

        // Overtype: typing a closing character right before an existing identical one.
        if Self.closerToOpener[char] != nil, range.length == 0 {
            if charAt(ns, range.location) == char {
                return TextEdit(range: NSRange(location: range.location, length: 1), replacement: String(char), selection: NSRange(location: range.location + 1, length: 0))
            }
            if Self.openerToCloser[char] == nil {
                // A pure closer (")" "]" "}") with no match ahead: no special handling.
                return nil
            }
        }

        guard let closer = Self.openerToCloser[char] else { return nil }

        if char == "'" {
            if range.location > 0, let prev = charAt(ns, range.location - 1), isAlphanumeric(prev) {
                return nil
            }
        }

        if range.length > 0 {
            let selText = ns.substring(with: range)
            let wrapped = String(char) + selText + String(closer)
            return TextEdit(range: range, replacement: wrapped, selection: NSRange(location: range.location + 1, length: (selText as NSString).length))
        } else {
            let inserted = String(char) + String(closer)
            return TextEdit(range: range, replacement: inserted, selection: NSRange(location: range.location + 1, length: 0))
        }
    }

    private func interceptBackspacePairDeletion(_ ns: NSString, range: NSRange) -> TextEdit? {
        // `range` is expected to be (position-1, 1): the single character being backspaced.
        let deleteEnd = range.location + range.length

        // Special-cased 2-char markdown marker pair: "**|**"
        if range.location >= 1 && deleteEnd + 1 <= ns.length {
            let twoBefore = NSRange(location: range.location - 1, length: 2)
            let twoAfter = NSRange(location: deleteEnd - 1, length: 2)
            if ns.substring(with: twoBefore) == "**" && ns.substring(with: twoAfter) == "**" {
                let fullRange = NSRange(location: range.location - 1, length: 4)
                return TextEdit(range: fullRange, replacement: "", selection: NSRange(location: fullRange.location, length: 0))
            }
        }

        guard autoCompleteBrackets else { return nil }
        guard let deletedChar = charAt(ns, range.location), let closer = Self.openerToCloser[deletedChar] else { return nil }
        guard let nextChar = charAt(ns, deleteEnd), nextChar == closer else { return nil }

        let fullRange = NSRange(location: range.location, length: 2)
        return TextEdit(range: fullRange, replacement: "", selection: NSRange(location: fullRange.location, length: 0))
    }

    private func charAt(_ ns: NSString, _ location: Int) -> Character? {
        guard location >= 0 && location < ns.length else { return nil }
        let unichar = ns.character(at: location)
        return Character(UnicodeScalar(unichar) ?? UnicodeScalar(0))
    }

    private func isAlphanumeric(_ c: Character) -> Bool {
        c.isLetter || c.isNumber
    }

    // MARK: - Tab

    private func interceptTab(_ ns: NSString, range: NSRange) -> TextEdit? {
        let paragraphRange = ns.lineRange(for: range)
        let lines = lineContentRanges(ns, paragraphRange)

        if lines.count > 1 {
            return indentLines(ns, paragraphRange: paragraphRange, lines: lines, selection: range)
        }

        let line = lines[0]
        let lineText = ns.substring(with: line)
        if let prefixLength = listOrQuotePrefixLength(lineText), range.location - line.location <= prefixLength {
            return indentLines(ns, paragraphRange: paragraphRange, lines: lines, selection: range)
        }

        guard insertSpacesForTab else { return nil }
        let column = range.location - line.location
        var spacesNeeded = tabWidth - (column % tabWidth)
        if spacesNeeded == 0 { spacesNeeded = tabWidth }
        let spaces = String(repeating: " ", count: spacesNeeded)
        return TextEdit(range: range, replacement: spaces, selection: NSRange(location: range.location + spaces.utf16.count, length: 0))
    }

    private func indentToken() -> String {
        insertSpacesForTab ? String(repeating: " ", count: tabWidth) : "\t"
    }

    private func indentLines(_ ns: NSString, paragraphRange: NSRange, lines: [NSRange], selection: NSRange) -> TextEdit? {
        let token = indentToken()
        let edits: [(range: NSRange, replacement: String)] = lines.map { (NSRange(location: $0.location, length: 0), token) }
        guard !edits.isEmpty else { return nil }

        var result = ""
        var cursor = paragraphRange.location
        for edit in edits {
            result += ns.substring(with: NSRange(location: cursor, length: edit.range.location - cursor))
            result += edit.replacement
            cursor = edit.range.location + edit.range.length
        }
        result += ns.substring(with: NSRange(location: cursor, length: paragraphRange.location + paragraphRange.length - cursor))

        func mapPosition(_ original: Int) -> Int {
            var delta = 0
            for edit in edits {
                let editEnd = edit.range.location + edit.range.length
                if editEnd <= original {
                    delta += edit.replacement.utf16.count - edit.range.length
                } else {
                    break
                }
            }
            return original + delta
        }

        let newStart = mapPosition(selection.location)
        let newEnd = mapPosition(selection.location + selection.length)
        return TextEdit(range: paragraphRange, replacement: result, selection: NSRange(location: newStart, length: max(0, newEnd - newStart)))
    }

    private func lineContentRanges(_ ns: NSString, _ paragraphRange: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = paragraphRange.location
        let end = paragraphRange.location + paragraphRange.length
        if paragraphRange.length == 0 {
            return [NSRange(location: location, length: 0)]
        }
        while location < end {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let clampedContentsEnd = min(contentsEnd, end)
            ranges.append(NSRange(location: location, length: max(0, clampedContentsEnd - location)))
            if lineEnd <= location { break }
            location = lineEnd
        }
        return ranges
    }

    private func listOrQuotePrefixLength(_ lineText: String) -> Int? {
        if let m = fullMatch(Self.taskRegex, in: lineText) {
            // indentation + marker + " [ ] "
            let group3End = m.range(at: 3).location + m.range(at: 3).length
            return group3End + 2 // "] "
        }
        if let m = fullMatch(Self.orderedRegex, in: lineText) {
            return m.range(at: 3).location + m.range(at: 3).length + 1 // separator + " "
        }
        if let m = fullMatch(Self.unorderedRegex, in: lineText) {
            return m.range(at: 2).location + m.range(at: 2).length + 1 // marker + " "
        }
        if let m = fullMatch(Self.blockquoteRegex, in: lineText) {
            return m.range(at: 1).length + 2 // indentation + "> "
        }
        return nil
    }
}
