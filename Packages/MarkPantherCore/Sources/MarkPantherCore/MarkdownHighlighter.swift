import Foundation

/// A visual style to apply to a range of Markdown source text.
public enum HighlightStyle: Sendable, Equatable, Hashable {
    case heading(level: Int), strong, emphasis, strikethrough, highlight, inlineCode, codeBlock,
         link, linkURL, image, blockquote, listMarker, horizontalRule, frontmatter, htmlComment, markup,
         codeFence, codeLanguage, tableMarkup, tableHeader, htmlTag, footnote, math, taskMarker,
         tocToken, hardBreak, escape
}

/// A single styled range of text.
public struct HighlightSpan: Equatable, Sendable {
    public var range: NSRange
    public var style: HighlightStyle

    public init(range: NSRange, style: HighlightStyle) {
        self.range = range
        self.style = style
    }
}

/// A lightweight, line-oriented Markdown syntax highlighter. Not a full
/// CommonMark parser — uses line scanning plus regexes, tuned for good
/// practical accuracy and speed on editor-sized documents.
public struct MarkdownHighlighter: Sendable {
    public init() {}

    // MARK: - Public API

    public func highlight(_ text: String) -> [HighlightSpan] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        return Self.scanDocument(ns)
    }

    public func highlight(_ text: String, in range: NSRange) -> [HighlightSpan] {
        let all = highlight(text)
        var result: [HighlightSpan] = []
        result.reserveCapacity(all.count)
        for span in all {
            let clipped = NSIntersectionRange(span.range, range)
            if clipped.length > 0 {
                result.append(HighlightSpan(range: clipped, style: span.style))
            }
        }
        return result
    }

    public func rangeToRehighlight(in text: String, editedRange: NSRange) -> NSRange {
        let ns = text as NSString
        let length = ns.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }

        let safeLocation = min(max(editedRange.location, 0), length)
        let safeEnd = min(max(editedRange.location + editedRange.length, safeLocation), length)
        let safeRange = NSRange(location: safeLocation, length: safeEnd - safeLocation)

        let paragraphRange = ns.paragraphRange(for: safeRange)
        let full = NSRange(location: 0, length: length)

        let touchedText = ns.substring(with: paragraphRange)
        if touchedText.contains("```") || touchedText.contains("~~~") || touchedText.contains("$$") {
            return full
        }
        for lineSub in touchedText.split(separator: "\n", omittingEmptySubsequences: false) {
            let t = lineSub.trimmingCharacters(in: .whitespaces)
            if t == "---" || t == "..." {
                return full
            }
            if Self.isTableSeparatorRow(t) {
                return full
            }
        }

        // A line strictly inside an already-open "$$" math block carries no
        // local "$$" marker of its own, so an edit there still needs the
        // whole document re-scanned to know the block is still open.
        if Self.isInsideOpenMathBlock(ns, before: paragraphRange.location) {
            return full
        }

        // Editing a table's header row or its delimiter row can change
        // whether the neighboring row is recognized as a table at all.
        if paragraphRange.location > 0 {
            let priorRange = ns.paragraphRange(for: NSRange(location: paragraphRange.location - 1, length: 0))
            if Self.isTableSeparatorRow(ns.substring(with: priorRange).trimmingCharacters(in: .whitespaces)) {
                return full
            }
        }
        let afterLocation = paragraphRange.location + paragraphRange.length
        if afterLocation < length {
            let nextRange = ns.paragraphRange(for: NSRange(location: afterLocation, length: 0))
            if Self.isTableSeparatorRow(ns.substring(with: nextRange).trimmingCharacters(in: .whitespaces)) {
                return full
            }
        }

        // Editing the document's very first line is only relevant to frontmatter
        // if that line (before or after the edit) could be a "---" delimiter;
        // the check above already covers the post-edit text.
        return paragraphRange
    }

    // MARK: - Regexes (all precompiled once)

    private static let atxHeadingRegex = try! NSRegularExpression(pattern: "^(#{1,6})(\\s+)(.*)$")
    private static let taskMarkerRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+])(\\s+)(\\[[ xX]\\])(\\s+)")
    private static let unorderedMarkerRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+])(\\s+)")
    private static let orderedMarkerRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d+[.)])(\\s+)")
    private static let blockquoteMarkerRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(>+)(\\s?)")

    private static let htmlCommentRegex = try! NSRegularExpression(pattern: "<!--.*?-->")
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private static let imageRegex = try! NSRegularExpression(pattern: "!\\[[^\\]\\n]*\\]\\([^)\\n]*\\)")
    private static let linkInlineRegex = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\(([^)\\n]*)\\)")
    private static let linkReferenceRegex = try! NSRegularExpression(pattern: "\\[([^\\]\\n]+)\\]\\[([^\\]\\n]*)\\]")
    private static let autolinkRegex = try! NSRegularExpression(pattern: "<https?://[^>\\s]+>")
    private static let bareURLRegex = try! NSRegularExpression(pattern: "https?://[^\\s)\\]<>]+")
    private static let strongRegex = try! NSRegularExpression(pattern: "\\*\\*[^*\\n]+?\\*\\*")
    private static let strikethroughRegex = try! NSRegularExpression(pattern: "~~[^~\\n]+?~~")
    private static let highlightRegex = try! NSRegularExpression(pattern: "==[^=\\n]+?==")
    private static let emphasisRegex = try! NSRegularExpression(pattern: "\\*[^*\\n]+?\\*")

    // Backslash escapes of CommonMark's ASCII punctuation set: matches the
    // backslash together with the single punctuation character it escapes.
    private static let escapeRegex = try! NSRegularExpression(
        pattern: ##"\\[!"#$%&'()*+,\-./:;<=>?@\[\]^_`{|}~]"##)

    // `$$...$$` on a single line (both delimiters present). Unlike the
    // single-`$` form there is no currency ambiguity to guard against, so
    // interior padding spaces ("$$ x^2 $$") are allowed.
    private static let mathBlockInlineRegex = try! NSRegularExpression(
        pattern: ##"\$\$[^\n]+?\$\$"##)
    // `$...$`. Requires the character right inside each delimiter to be
    // non-whitespace, and refuses to close right before a digit, so plain
    // currency like "$5 and $10" is left alone.
    private static let mathInlineRegex = try! NSRegularExpression(
        pattern: ##"\$(?=\S)[^\n]*?(?<=\S)\$(?!\d)"##)

    // Footnote reference `[^id]`, excluding the label of a definition line
    // (`[^id]:`), which is handled separately at the block level.
    private static let footnoteRefRegex = try! NSRegularExpression(pattern: ##"\[\^([^\]\n]+)\](?!:)"##)
    private static let footnoteDefRegex = try! NSRegularExpression(pattern: ##"^\[\^([^\]\n]+)\]:"##)

    // Consumed (but not styled) so a `<user@example.com>` autolink is never
    // mistaken for a raw HTML tag.
    private static let emailAutolinkMaskRegex = try! NSRegularExpression(pattern: ##"<[a-zA-Z0-9._%+-]+@[^<>\s]+>"##)
    private static let htmlTagRegex = try! NSRegularExpression(pattern: ##"</?[a-zA-Z][^<>\n]*>"##)

    private static let escapedPipeRegex = try! NSRegularExpression(pattern: #"\\\|"#)
    private static let tableSeparatorRegex = try! NSRegularExpression(
        pattern: ##"^\|?[ \t]*:?-+:?[ \t]*(\|[ \t]*:?-+:?[ \t]*)*\|?$"##)
    private static let fenceInfoStringRegex = try! NSRegularExpression(
        pattern: ##"^[ \t]{0,3}(`{3,}|~{3,})[ \t]*(\S.*?)?[ \t]*$"##)

    // MARK: - Document scanning

    private static func scanDocument(_ ns: NSString) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let lines = lineRanges(ns)
        guard !lines.isEmpty else { return [] }

        var idx = 0

        // Frontmatter: only recognized at the very start of the document, and
        // only when a closing delimiter is actually found (otherwise a lone
        // leading "---" is just a horizontal rule).
        let firstTrimmed = ns.substring(with: lines[0]).trimmingCharacters(in: .whitespaces)
        if firstTrimmed == "---" {
            var closeIdx: Int? = nil
            var i = 1
            while i < lines.count {
                let t = ns.substring(with: lines[i]).trimmingCharacters(in: .whitespaces)
                if t == "---" || t == "..." {
                    closeIdx = i
                    break
                }
                i += 1
            }
            if let end = closeIdx {
                for j in 0...end {
                    spans.append(HighlightSpan(range: lines[j], style: .frontmatter))
                }
                idx = end + 1
            }
        }

        var inFence = false
        var fenceChar: Character = "`"
        var inMathBlock = false

        while idx < lines.count {
            let line = lines[idx]

            if inFence {
                spans.append(HighlightSpan(range: line, style: .codeBlock))
                let trimmed = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
                if isFenceClose(trimmed, fenceChar: fenceChar) {
                    inFence = false
                    spans.append(HighlightSpan(range: line, style: .codeFence))
                }
                idx += 1
                continue
            }

            if inMathBlock {
                spans.append(HighlightSpan(range: line, style: .math))
                let trimmed = ns.substring(with: line).trimmingCharacters(in: .whitespaces)
                if trimmed == "$$" {
                    inMathBlock = false
                }
                idx += 1
                continue
            }

            let lineText = ns.substring(with: line)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)

            if let fc = fenceOpenChar(trimmed) {
                inFence = true
                fenceChar = fc
                spans.append(HighlightSpan(range: line, style: .codeBlock))
                spans.append(HighlightSpan(range: line, style: .codeFence))
                if let langSpan = fenceLanguageSpan(line: line, lineText: lineText) {
                    spans.append(langSpan)
                }
                idx += 1
                continue
            }

            if trimmed == "$$" {
                inMathBlock = true
                spans.append(HighlightSpan(range: line, style: .math))
                idx += 1
                continue
            }

            if trimmed.isEmpty {
                idx += 1
                continue
            }

            // ATX heading
            let fullLineRange = NSRange(location: 0, length: (lineText as NSString).length)
            if let m = atxHeadingRegex.firstMatch(in: lineText, range: fullLineRange) {
                let level = m.range(at: 1).length
                spans.append(HighlightSpan(range: line, style: .heading(level: level)))
                let markupLength = m.range(at: 1).length + m.range(at: 2).length
                spans.append(HighlightSpan(range: NSRange(location: line.location, length: markupLength), style: .markup))
                spans.append(contentsOf: inlineSpans(ns, in: line))
                idx += 1
                continue
            }

            // Setext heading (lookahead to next line)
            if idx + 1 < lines.count {
                let nextTrimmed = ns.substring(with: lines[idx + 1]).trimmingCharacters(in: .whitespaces)
                if isSetextUnderline(nextTrimmed, char: "=") {
                    spans.append(HighlightSpan(range: line, style: .heading(level: 1)))
                    spans.append(contentsOf: inlineSpans(ns, in: line))
                    spans.append(HighlightSpan(range: lines[idx + 1], style: .markup))
                    idx += 2
                    continue
                } else if isSetextUnderline(nextTrimmed, char: "-") {
                    spans.append(HighlightSpan(range: line, style: .heading(level: 2)))
                    spans.append(contentsOf: inlineSpans(ns, in: line))
                    spans.append(HighlightSpan(range: lines[idx + 1], style: .markup))
                    idx += 2
                    continue
                }
            }

            // Horizontal rule
            if isHorizontalRule(trimmed) {
                spans.append(HighlightSpan(range: line, style: .horizontalRule))
                idx += 1
                continue
            }

            // Standalone [TOC] token
            if trimmed == "[TOC]" {
                spans.append(HighlightSpan(range: line, style: .tocToken))
                idx += 1
                continue
            }

            // GFM table: a non-blank line immediately followed by a valid
            // delimiter row starts a table (header + delimiter + body rows,
            // consumed until the next blank line).
            if let sepRange = tableSeparatorLookahead(ns, lines: lines, headerIdx: idx) {
                spans.append(contentsOf: tableRowSpans(ns, line: line, isHeader: true))
                spans.append(HighlightSpan(range: sepRange, style: .tableMarkup))
                idx += 2
                while idx < lines.count {
                    let bodyLine = lines[idx]
                    let bodyTrimmed = ns.substring(with: bodyLine).trimmingCharacters(in: .whitespaces)
                    if bodyTrimmed.isEmpty { break }
                    spans.append(contentsOf: tableRowSpans(ns, line: bodyLine, isHeader: false))
                    idx += 1
                }
                continue
            }

            // Blockquote
            if let m = blockquoteMarkerRegex.firstMatch(in: lineText, range: fullLineRange) {
                let markerRange = m.range(at: 2)
                spans.append(HighlightSpan(range: NSRange(location: line.location + markerRange.location, length: markerRange.length), style: .blockquote))
                spans.append(contentsOf: inlineSpans(ns, in: line))
                idx += 1
                continue
            }

            // List marker (task / ordered / unordered)
            if let markerSpans = listMarkerSpans(line: line, lineText: lineText, fullLineRange: fullLineRange) {
                spans.append(contentsOf: markerSpans)
                spans.append(contentsOf: inlineSpans(ns, in: line))
                idx += 1
                continue
            }

            // Footnote definition line: "[^id]: ..."
            if let m = footnoteDefRegex.firstMatch(in: lineText, range: fullLineRange) {
                spans.append(HighlightSpan(range: NSRange(location: line.location + m.range.location, length: m.range.length), style: .footnote))
                spans.append(contentsOf: inlineSpans(ns, in: line))
                idx += 1
                continue
            }

            // Plain paragraph line
            spans.append(contentsOf: inlineSpans(ns, in: line))
            idx += 1
        }

        return spans
    }

    // MARK: - Line-level helpers

    private static func lineRanges(_ ns: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        let end = ns.length
        if end == 0 { return [] }
        while location < end {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            ranges.append(NSRange(location: lineStart, length: contentsEnd - lineStart))
            if lineEnd <= location { break }
            location = lineEnd
        }
        return ranges
    }

    private static func fenceOpenChar(_ trimmed: String) -> Character? {
        if trimmed.hasPrefix("```") { return "`" }
        if trimmed.hasPrefix("~~~") { return "~" }
        return nil
    }

    private static func isFenceClose(_ trimmed: String, fenceChar: Character) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == fenceChar }
    }

    private static func isSetextUnderline(_ trimmed: String, char: Character) -> Bool {
        !trimmed.isEmpty && trimmed.allSatisfy { $0 == char }
    }

    private static func isHorizontalRule(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, "-*_".contains(first) else { return false }
        let stripped = trimmed.filter { $0 != " " }
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    /// Extracts the info-string (language name) range of a fence-open line,
    /// e.g. the "swift" in "```swift". Returns `nil` when there is none.
    private static func fenceLanguageSpan(line: NSRange, lineText: String) -> HighlightSpan? {
        let nsLineText = lineText as NSString
        let full = NSRange(location: 0, length: nsLineText.length)
        guard let m = fenceInfoStringRegex.firstMatch(in: lineText, range: full) else { return nil }
        let infoGroup = m.range(at: 2)
        guard infoGroup.location != NSNotFound, infoGroup.length > 0 else { return nil }
        return HighlightSpan(range: NSRange(location: line.location + infoGroup.location, length: infoGroup.length), style: .codeLanguage)
    }

    private static func listMarkerSpans(line: NSRange, lineText: String, fullLineRange: NSRange) -> [HighlightSpan]? {
        if let m = taskMarkerRegex.firstMatch(in: lineText, range: fullLineRange) {
            let bulletRange = m.range(at: 2)
            let boxRange = m.range(at: 4)
            return [
                HighlightSpan(range: NSRange(location: line.location + bulletRange.location, length: bulletRange.length), style: .listMarker),
                HighlightSpan(range: NSRange(location: line.location + boxRange.location, length: boxRange.length), style: .taskMarker),
            ]
        }
        if let m = orderedMarkerRegex.firstMatch(in: lineText, range: fullLineRange) {
            let numberRange = m.range(at: 2)
            return [HighlightSpan(range: NSRange(location: line.location + numberRange.location, length: numberRange.length), style: .listMarker)]
        }
        if let m = unorderedMarkerRegex.firstMatch(in: lineText, range: fullLineRange) {
            let bulletRange = m.range(at: 2)
            return [HighlightSpan(range: NSRange(location: line.location + bulletRange.location, length: bulletRange.length), style: .listMarker)]
        }
        return nil
    }

    // MARK: - Tables

    private static func isTableSeparatorRow(_ trimmed: String) -> Bool {
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let ns = trimmed as NSString
        let full = NSRange(location: 0, length: ns.length)
        return tableSeparatorRegex.firstMatch(in: trimmed, range: full) != nil
    }

    /// If `lines[headerIdx + 1]` is a valid GFM delimiter row, returns its
    /// range (so the header line at `headerIdx` should be treated as a
    /// table header). Otherwise `nil`.
    private static func tableSeparatorLookahead(_ ns: NSString, lines: [NSRange], headerIdx: Int) -> NSRange? {
        guard headerIdx + 1 < lines.count else { return nil }
        let sepRange = lines[headerIdx + 1]
        let sepTrimmed = ns.substring(with: sepRange).trimmingCharacters(in: .whitespaces)
        return isTableSeparatorRow(sepTrimmed) ? sepRange : nil
    }

    /// Offsets (relative to `line`) of the `|` characters that act as real
    /// cell delimiters — i.e. not inside inline code and not escaped (`\|`).
    private static func tableCellPipeOffsets(_ ns: NSString, in line: NSRange) -> [Int] {
        guard line.length > 0 else { return [] }
        var buffer: [unichar] = (0..<line.length).map { ns.character(at: line.location + $0) }

        func mask(_ r: NSRange) {
            guard r.location >= 0, r.location + r.length <= buffer.count else { return }
            for i in r.location..<(r.location + r.length) { buffer[i] = 0x0A }
        }
        func currentString() -> NSString {
            buffer.withUnsafeBufferPointer { NSString(characters: $0.baseAddress!, length: $0.count) }
        }

        let full = NSRange(location: 0, length: buffer.count)
        for m in inlineCodeRegex.matches(in: currentString() as String, range: full) {
            mask(m.range)
        }
        for m in escapedPipeRegex.matches(in: currentString() as String, range: full) {
            mask(m.range)
        }

        var offsets: [Int] = []
        for i in 0..<buffer.count where buffer[i] == 0x7C {
            offsets.append(i)
        }
        return offsets
    }

    /// Trims leading/trailing whitespace off a range relative to `line` and
    /// converts it to an absolute NSRange; `nil` if nothing but whitespace remains.
    private static func trimmedAbsoluteRange(_ ns: NSString, line: NSRange, relative: NSRange) -> NSRange? {
        guard relative.length > 0 else { return nil }
        let absStart = line.location + relative.location
        var start = 0
        var end = relative.length
        while start < end, isWhitespaceUnichar(ns.character(at: absStart + start)) { start += 1 }
        while end > start, isWhitespaceUnichar(ns.character(at: absStart + end - 1)) { end -= 1 }
        guard end > start else { return nil }
        return NSRange(location: absStart + start, length: end - start)
    }

    private static func isWhitespaceUnichar(_ u: unichar) -> Bool {
        u == 0x20 || u == 0x09
    }

    /// Builds the spans for one row of a table: `.tableMarkup` for each real
    /// `|`, `.tableHeader` for each header cell's trimmed text (header rows
    /// only), plus the row's ordinary inline spans (code/links/emphasis/...).
    private static func tableRowSpans(_ ns: NSString, line: NSRange, isHeader: Bool) -> [HighlightSpan] {
        var spans: [HighlightSpan] = []
        let offsets = tableCellPipeOffsets(ns, in: line)
        for off in offsets {
            spans.append(HighlightSpan(range: NSRange(location: line.location + off, length: 1), style: .tableMarkup))
        }

        if isHeader {
            var boundaries: [Int] = [-1]
            boundaries.append(contentsOf: offsets)
            boundaries.append(line.length)
            for i in 0..<(boundaries.count - 1) {
                let start = boundaries[i] + 1
                let end = boundaries[i + 1]
                guard end > start else { continue }
                let relRange = NSRange(location: start, length: end - start)
                if let trimmedAbs = trimmedAbsoluteRange(ns, line: line, relative: relRange) {
                    spans.append(HighlightSpan(range: trimmedAbs, style: .tableHeader))
                }
            }
        }

        spans.append(contentsOf: inlineSpans(ns, in: line))
        return spans
    }

    // MARK: - Math blocks (for rangeToRehighlight)

    private static func isInsideOpenMathBlock(_ ns: NSString, before location: Int) -> Bool {
        var inBlock = false
        for r in lineRanges(ns) {
            if r.location >= location { break }
            if ns.substring(with: r).trimmingCharacters(in: .whitespaces) == "$$" {
                inBlock.toggle()
            }
        }
        return inBlock
    }

    // MARK: - Inline scanning

    /// Scans a single line for inline constructs (emphasis, links, code, ...).
    ///
    /// Rather than post-filtering overlapping regex matches (which lets a
    /// "leftover" delimiter character from an already-consumed higher-priority
    /// match — e.g. the second `*` of a `**` pair — bleed into a later,
    /// lower-priority match and corrupt it), already-matched ranges are
    /// masked out with `\n` before the next pattern runs. Every one of our
    /// inline regexes excludes `\n` from its content class, so a masked
    /// range can never be matched into or across by a subsequent pass.
    private static func inlineSpans(_ ns: NSString, in line: NSRange) -> [HighlightSpan] {
        let lineText = ns.substring(with: line)
        var buffer: [unichar] = (0..<line.length).map { ns.character(at: line.location + $0) }
        var spans: [HighlightSpan] = []

        func absolute(_ r: NSRange) -> NSRange {
            NSRange(location: line.location + r.location, length: r.length)
        }
        func mask(_ r: NSRange) {
            guard r.location >= 0, r.location + r.length <= buffer.count else { return }
            for i in r.location..<(r.location + r.length) {
                buffer[i] = 0x0A // '\n' — excluded from every content class below.
            }
        }

        // Hard line break: a trailing backslash, or a trailing run of 2+
        // spaces. Checked directly against the (still unmasked) buffer so it
        // works correctly with UTF-16 surrogate pairs at line end.
        if let lastIdx = buffer.indices.last {
            if buffer[lastIdx] == 0x5C {
                let r = NSRange(location: lastIdx, length: 1)
                spans.append(HighlightSpan(range: absolute(r), style: .hardBreak))
                mask(r)
            } else if buffer[lastIdx] == 0x20 {
                var start = lastIdx
                while start > 0, buffer[start - 1] == 0x20 { start -= 1 }
                let count = lastIdx - start + 1
                if count >= 2 {
                    let r = NSRange(location: start, length: count)
                    spans.append(HighlightSpan(range: absolute(r), style: .hardBreak))
                    mask(r)
                }
            }
        }

        func currentString() -> NSString {
            buffer.withUnsafeBufferPointer { NSString(characters: $0.baseAddress!, length: $0.count) }
        }
        // `lineText` (pre-mask) is used only to cheaply rule out patterns that
        // cannot possibly be present, skipping the regex pass entirely — this
        // is safe because masking only removes characters, never adds them.
        func scan(_ regex: NSRegularExpression, ifLineContains needle: String, _ handle: (NSTextCheckingResult) -> Void) {
            guard !buffer.isEmpty, lineText.contains(needle) else { return }
            let current = currentString()
            let full = NSRange(location: 0, length: current.length)
            for m in regex.matches(in: current as String, range: full) {
                handle(m)
                mask(m.range)
            }
        }

        scan(htmlCommentRegex, ifLineContains: "<!--") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .htmlComment))
        }

        scan(inlineCodeRegex, ifLineContains: "`") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .inlineCode))
        }

        scan(escapeRegex, ifLineContains: "\\") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .escape))
        }

        scan(mathBlockInlineRegex, ifLineContains: "$$") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .math))
        }

        scan(mathInlineRegex, ifLineContains: "$") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .math))
        }

        scan(imageRegex, ifLineContains: "![") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .image))
        }

        scan(linkInlineRegex, ifLineContains: "](") { m in
            let full = m.range
            let textGroup = m.range(at: 1)
            let urlGroup = m.range(at: 2)
            spans.append(HighlightSpan(range: absolute(textGroup), style: .link))
            if urlGroup.length > 0 {
                spans.append(HighlightSpan(range: absolute(urlGroup), style: .linkURL))
            }
            let openBracket = NSRange(location: full.location, length: 1)
            let closeBracket = NSRange(location: textGroup.location + textGroup.length, length: 1)
            let openParen = NSRange(location: closeBracket.location + 1, length: 1)
            let closeParen = NSRange(location: full.location + full.length - 1, length: 1)
            for r in [openBracket, closeBracket, openParen, closeParen] {
                spans.append(HighlightSpan(range: absolute(r), style: .markup))
            }
        }

        scan(linkReferenceRegex, ifLineContains: "][") { m in
            let textGroup = m.range(at: 1)
            spans.append(HighlightSpan(range: absolute(textGroup), style: .link))
        }

        scan(footnoteRefRegex, ifLineContains: "[^") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .footnote))
        }

        scan(autolinkRegex, ifLineContains: "<http") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .linkURL))
        }

        // Consumed silently so an email autolink is never mistaken for raw HTML.
        scan(emailAutolinkMaskRegex, ifLineContains: "@") { _ in }

        scan(htmlTagRegex, ifLineContains: "<") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .htmlTag))
        }

        if lineText.contains("http://") || lineText.contains("https://") {
            scan(bareURLRegex, ifLineContains: "http") { m in
                spans.append(HighlightSpan(range: absolute(m.range), style: .linkURL))
            }
        }

        scan(strongRegex, ifLineContains: "**") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .strong))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location, length: 2)), style: .markup))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location + m.range.length - 2, length: 2)), style: .markup))
        }

        scan(strikethroughRegex, ifLineContains: "~~") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .strikethrough))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location, length: 2)), style: .markup))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location + m.range.length - 2, length: 2)), style: .markup))
        }

        scan(highlightRegex, ifLineContains: "==") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .highlight))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location, length: 2)), style: .markup))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location + m.range.length - 2, length: 2)), style: .markup))
        }

        scan(emphasisRegex, ifLineContains: "*") { m in
            spans.append(HighlightSpan(range: absolute(m.range), style: .emphasis))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location, length: 1)), style: .markup))
            spans.append(HighlightSpan(range: absolute(NSRange(location: m.range.location + m.range.length - 1, length: 1)), style: .markup))
        }

        return spans
    }
}
