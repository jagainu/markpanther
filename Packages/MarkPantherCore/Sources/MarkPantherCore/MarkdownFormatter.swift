import Foundation

/// A Format-menu command.
public enum FormatCommand: Sendable, Equatable, CaseIterable {
    case strong, emphasis, underline, strikethrough, highlight, inlineCode, link, image,
         unorderedList, orderedList, blockquote, comment, shiftLeft, shiftRight
    case heading(Int)

    public static var allCases: [FormatCommand] {
        [.strong, .emphasis, .underline, .strikethrough, .highlight, .inlineCode, .link, .image,
         .unorderedList, .orderedList, .blockquote, .comment, .shiftLeft, .shiftRight]
    }
}

/// Applies a Format-menu command as a pure function over text + selection,
/// toggling the markup off when it is already there. All ranges are UTF-16
/// based (`NSRange`).
public struct MarkdownFormatter: Sendable {
    public var listMarker: String
    public var indentUnit: String

    public init(listMarker: String = "-", indentUnit: String = "    ") {
        self.listMarker = listMarker
        self.indentUnit = indentUnit
    }

    public func apply(_ command: FormatCommand, to text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        switch command {
        case .strong:
            return toggleSymmetric(ns, selection, open: "**", close: "**")
        case .emphasis:
            return toggleSymmetric(ns, selection, open: "*", close: "*", excludeOpen: "**", excludeClose: "**")
        case .underline:
            return toggleSymmetric(ns, selection, open: "_", close: "_")
        case .strikethrough:
            return toggleSymmetric(ns, selection, open: "~~", close: "~~")
        case .highlight:
            return toggleSymmetric(ns, selection, open: "==", close: "==")
        case .inlineCode:
            return toggleSymmetric(ns, selection, open: "`", close: "`")
        case .comment:
            return toggleSymmetric(ns, selection, open: "<!-- ", close: " -->")
        case .link:
            return applyLinkOrImage(ns, selection, isImage: false)
        case .image:
            return applyLinkOrImage(ns, selection, isImage: true)
        case .heading(let level):
            return applyHeading(ns, selection, level: level)
        case .unorderedList:
            return applyList(ns, selection, ordered: false)
        case .orderedList:
            return applyList(ns, selection, ordered: true)
        case .blockquote:
            return applyLinePrefixToggle(ns, selection, prefix: "> ", matches: { Self.blockquoteRegex.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) })
        case .shiftRight:
            return shiftLines(ns, selection, right: true)
        case .shiftLeft:
            return shiftLines(ns, selection, right: false)
        }
    }

    // MARK: - Symmetric inline markers (strong/emphasis/underline/etc.)

    private func isPrecededBy(_ ns: NSString, _ location: Int, marker: String) -> Bool {
        let len = marker.utf16.count
        guard len > 0, location - len >= 0 else { return false }
        return ns.substring(with: NSRange(location: location - len, length: len)) == marker
    }

    private func isFollowedBy(_ ns: NSString, _ location: Int, marker: String) -> Bool {
        let len = marker.utf16.count
        guard len > 0, location + len <= ns.length else { return false }
        return ns.substring(with: NSRange(location: location, length: len)) == marker
    }

    private func preciseBefore(_ ns: NSString, _ location: Int, marker: String, excluding: String?) -> Bool {
        guard isPrecededBy(ns, location, marker: marker) else { return false }
        if let excluding, isPrecededBy(ns, location, marker: excluding) { return false }
        return true
    }

    private func preciseAfter(_ ns: NSString, _ location: Int, marker: String, excluding: String?) -> Bool {
        guard isFollowedBy(ns, location, marker: marker) else { return false }
        if let excluding, isFollowedBy(ns, location, marker: excluding) { return false }
        return true
    }

    /// Toggles a symmetric (or open/close) marker pair around `selection`.
    private func toggleSymmetric(
        _ ns: NSString, _ selection: NSRange,
        open: String, close: String,
        excludeOpen: String? = nil, excludeClose: String? = nil
    ) -> TextEdit? {
        let openLen = open.utf16.count
        let closeLen = close.utf16.count

        if selection.length == 0 {
            let loc = selection.location
            let hasOpenBefore = preciseBefore(ns, loc, marker: open, excluding: excludeOpen)
            let hasCloseAfter = preciseAfter(ns, loc, marker: close, excluding: excludeClose)
            if hasOpenBefore && hasCloseAfter {
                let range = NSRange(location: loc - openLen, length: openLen + closeLen)
                return TextEdit(range: range, replacement: "", selection: NSRange(location: range.location, length: 0))
            }
            let inserted = open + close
            return TextEdit(range: NSRange(location: loc, length: 0), replacement: inserted, selection: NSRange(location: loc + openLen, length: 0))
        }

        let selText = ns.substring(with: selection)

        func hasPrefixExact(_ s: String, marker: String, excluding: String?) -> Bool {
            guard s.hasPrefix(marker) else { return false }
            if let excluding, s.hasPrefix(excluding) { return false }
            return true
        }
        func hasSuffixExact(_ s: String, marker: String, excluding: String?) -> Bool {
            guard s.hasSuffix(marker) else { return false }
            if let excluding, s.hasSuffix(excluding) { return false }
            return true
        }

        let insideWrapped = hasPrefixExact(selText, marker: open, excluding: excludeOpen)
            && hasSuffixExact(selText, marker: close, excluding: excludeClose)
            && selText.utf16.count >= openLen + closeLen

        let outsideWrapped = preciseBefore(ns, selection.location, marker: open, excluding: excludeOpen)
            && preciseAfter(ns, selection.location + selection.length, marker: close, excluding: excludeClose)

        if insideWrapped {
            let innerRange = NSRange(location: selection.location + openLen, length: selection.length - openLen - closeLen)
            let inner = ns.substring(with: innerRange)
            return TextEdit(range: selection, replacement: inner, selection: NSRange(location: selection.location, length: inner.utf16.count))
        } else if outsideWrapped {
            let fullRange = NSRange(location: selection.location - openLen, length: openLen + selection.length + closeLen)
            return TextEdit(range: fullRange, replacement: selText, selection: NSRange(location: fullRange.location, length: selText.utf16.count))
        } else {
            let wrapped = open + selText + close
            return TextEdit(range: selection, replacement: wrapped, selection: NSRange(location: selection.location + openLen, length: selText.utf16.count))
        }
    }

    // MARK: - Link / Image

    private func applyLinkOrImage(_ ns: NSString, _ selection: NSRange, isImage: Bool) -> TextEdit? {
        let prefix = isImage ? "!" : ""
        let selText = selection.length > 0 ? ns.substring(with: selection) : ""
        let looksLikeURL = selText.hasPrefix("http://") || selText.hasPrefix("https://")

        if looksLikeURL {
            let replacement = "\(prefix)[](\(selText))"
            let caretOffset = prefix.utf16.count + 1 // right after "["
            return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + caretOffset, length: 0))
        } else {
            let replacement = "\(prefix)[\(selText)](url)"
            let urlOffset = prefix.utf16.count + 1 + selText.utf16.count + 2 // after "prefix[text]("
            return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + urlOffset, length: 3))
        }
    }

    // MARK: - Line-based helpers shared by heading/list/blockquote/shift

    /// Returns the content ranges (excluding line terminators) of each line
    /// touched by `range`, after first expanding `range` to full line boundaries.
    private func expandedLineRanges(_ ns: NSString, _ range: NSRange) -> (paragraphRange: NSRange, lines: [NSRange]) {
        let paragraphRange = ns.lineRange(for: range)
        var ranges: [NSRange] = []
        var location = paragraphRange.location
        let end = paragraphRange.location + paragraphRange.length
        if paragraphRange.length == 0 {
            ranges.append(NSRange(location: location, length: 0))
        } else {
            while location < end {
                var lineStart = 0, lineEnd = 0, contentsEnd = 0
                ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
                let clampedContentsEnd = min(contentsEnd, end)
                ranges.append(NSRange(location: location, length: max(0, clampedContentsEnd - location)))
                if lineEnd <= location { break }
                location = lineEnd
            }
        }
        return (paragraphRange, ranges)
    }

    /// Combines a set of small, non-overlapping edits (in absolute document
    /// coordinates, all contained within `paragraphRange`) into a single
    /// `TextEdit` spanning `paragraphRange`, remapping `selection` through them.
    private func combineLineEdits(
        _ ns: NSString,
        paragraphRange: NSRange,
        edits: [(range: NSRange, replacement: String)],
        selection: NSRange
    ) -> TextEdit? {
        guard !edits.isEmpty else { return nil }
        let sorted = edits.sorted { $0.range.location < $1.range.location }

        var result = ""
        var cursor = paragraphRange.location
        for edit in sorted {
            result += ns.substring(with: NSRange(location: cursor, length: edit.range.location - cursor))
            result += edit.replacement
            cursor = edit.range.location + edit.range.length
        }
        result += ns.substring(with: NSRange(location: cursor, length: paragraphRange.location + paragraphRange.length - cursor))

        let originalText = ns.substring(with: paragraphRange)
        if result == originalText { return nil }

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

        let newStart = mapPosition(selection.location)
        let newEnd = mapPosition(selection.location + selection.length)
        return TextEdit(range: paragraphRange, replacement: result, selection: NSRange(location: newStart, length: max(0, newEnd - newStart)))
    }

    // MARK: - Heading

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6}) ")

    private func applyHeading(_ ns: NSString, _ selection: NSRange, level: Int) -> TextEdit? {
        let clampedLevel = max(1, min(6, level))
        let (paragraphRange, lines) = expandedLineRanges(ns, selection)
        var edits: [(range: NSRange, replacement: String)] = []
        let newPrefix = String(repeating: "#", count: clampedLevel) + " "

        for line in lines {
            let lineText = ns.substring(with: line)
            let nsLine = lineText as NSString
            if let match = Self.headingRegex.firstMatch(in: lineText, range: NSRange(location: 0, length: nsLine.length)) {
                let matchLevel = match.range(at: 1).length
                let matchRange = NSRange(location: line.location + match.range.location, length: match.range.length)
                if matchLevel == clampedLevel {
                    edits.append((matchRange, ""))
                } else {
                    edits.append((matchRange, newPrefix))
                }
            } else {
                edits.append((NSRange(location: line.location, length: 0), newPrefix))
            }
        }

        return combineLineEdits(ns, paragraphRange: paragraphRange, edits: edits, selection: selection)
    }

    // MARK: - Lists

    private static let unorderedRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]) ")
    private static let orderedRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d+)([.)]) ")

    private func applyList(_ ns: NSString, _ selection: NSRange, ordered: Bool) -> TextEdit? {
        let (paragraphRange, lines) = expandedLineRanges(ns, selection)

        // Special case: exactly one blank line selected -> insert a marker.
        if lines.count == 1 && lines[0].length == 0 {
            let newPrefix = ordered ? "1. " : "\(listMarker) "
            let edits: [(range: NSRange, replacement: String)] = [(NSRange(location: lines[0].location, length: 0), newPrefix)]
            return combineLineEdits(ns, paragraphRange: paragraphRange, edits: edits, selection: selection)
        }

        let nonBlank = lines.filter { $0.length > 0 }
        guard !nonBlank.isEmpty else { return nil }

        func matchInfo(_ line: NSRange) -> (isThisType: Bool, existingMatch: NSTextCheckingResult?, isOrderedMatch: Bool) {
            let lineText = ns.substring(with: line)
            let nsLine = lineText as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if let m = Self.orderedRegex.firstMatch(in: lineText, range: fullRange) {
                return (ordered, m, true)
            }
            if let m = Self.unorderedRegex.firstMatch(in: lineText, range: fullRange) {
                return (!ordered, m, false)
            }
            return (false, nil, false)
        }

        let infos = nonBlank.map { ($0, matchInfo($0)) }
        let allAlreadyThisType = infos.allSatisfy { $0.1.isThisType }

        var edits: [(range: NSRange, replacement: String)] = []

        if allAlreadyThisType {
            for (line, info) in infos {
                guard let match = info.existingMatch else { continue }
                let matchRange = NSRange(location: line.location + match.range.location, length: match.range.length)
                edits.append((matchRange, ""))
            }
        } else {
            var number = 1
            for (line, info) in infos {
                let newPrefix = ordered ? "\(number). " : "\(listMarker) "
                if ordered { number += 1 }
                if let match = info.existingMatch {
                    let matchRange = NSRange(location: line.location + match.range.location, length: match.range.length)
                    edits.append((matchRange, newPrefix))
                } else {
                    edits.append((NSRange(location: line.location, length: 0), newPrefix))
                }
            }
        }

        return combineLineEdits(ns, paragraphRange: paragraphRange, edits: edits, selection: selection)
    }

    // MARK: - Blockquote (and generic line-prefix toggle)

    private static let blockquoteRegex = try! NSRegularExpression(pattern: "^([ \\t]*)> ")

    private func applyLinePrefixToggle(
        _ ns: NSString, _ selection: NSRange, prefix: String,
        matches: (String) -> NSTextCheckingResult?
    ) -> TextEdit? {
        let (paragraphRange, lines) = expandedLineRanges(ns, selection)

        if lines.count == 1 && lines[0].length == 0 {
            let edits: [(range: NSRange, replacement: String)] = [(NSRange(location: lines[0].location, length: 0), prefix)]
            return combineLineEdits(ns, paragraphRange: paragraphRange, edits: edits, selection: selection)
        }

        let nonBlank = lines.filter { $0.length > 0 }
        guard !nonBlank.isEmpty else { return nil }

        func existingMatch(_ line: NSRange) -> NSTextCheckingResult? {
            let lineText = ns.substring(with: line)
            return matches(lineText)
        }

        let infos = nonBlank.map { ($0, existingMatch($0)) }
        let allAlreadyMarked = infos.allSatisfy { $0.1 != nil }

        var edits: [(range: NSRange, replacement: String)] = []
        if allAlreadyMarked {
            for (line, match) in infos {
                guard let match else { continue }
                let matchRange = NSRange(location: line.location + match.range.location, length: match.range.length)
                edits.append((matchRange, ""))
            }
        } else {
            for (line, match) in infos {
                if match == nil {
                    edits.append((NSRange(location: line.location, length: 0), prefix))
                }
            }
        }

        return combineLineEdits(ns, paragraphRange: paragraphRange, edits: edits, selection: selection)
    }

    // MARK: - Shift left / right

    private func shiftLines(_ ns: NSString, _ selection: NSRange, right: Bool) -> TextEdit? {
        let (paragraphRange, lines) = expandedLineRanges(ns, selection)
        var edits: [(range: NSRange, replacement: String)] = []

        for line in lines {
            if right {
                edits.append((NSRange(location: line.location, length: 0), indentUnit))
            } else {
                let lineText = ns.substring(with: line)
                if lineText.hasPrefix("\t") {
                    edits.append((NSRange(location: line.location, length: 1), ""))
                } else {
                    let leadingSpaces = lineText.prefix { $0 == " " }
                    if leadingSpaces.isEmpty { continue }
                    let removeCount = min(leadingSpaces.count, indentUnit.utf16.count)
                    edits.append((NSRange(location: line.location, length: removeCount), ""))
                }
            }
        }

        return combineLineEdits(ns, paragraphRange: paragraphRange, edits: edits, selection: selection)
    }
}
