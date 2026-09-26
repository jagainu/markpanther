import Foundation

/// The little that fits on a Finder thumbnail: a title and the opening lines.
///
/// The thumbnail extension draws this with AppKit rather than rendering the
/// document, so a folder full of Markdown doesn't start a web view per icon.
/// Markup is therefore flattened to plain readable text here.
public struct ThumbnailSummary: Sendable, Equatable {
    public let title: String?
    public let lines: [String]

    public init(title: String?, lines: [String]) {
        self.title = title
        self.lines = lines
    }

    public static func make(from markdown: String, maxLines: Int = 12) -> ThumbnailSummary {
        var title: String?
        var lines: [String] = []
        var inFence = false
        var isFirstContentLine = true

        var iterator = Self.body(of: markdown).makeIterator()
        var pending: String?

        while lines.count < maxLines, let raw = pending.map({ p -> String in pending = nil; return p }) ?? iterator.next() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence || trimmed.isEmpty || isRule(trimmed) || isTableSeparator(trimmed) { continue }

            if trimmed.hasPrefix("#") {
                let text = clean(trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
                guard !text.isEmpty else { continue }
                if title == nil, isFirstContentLine { title = text } else { lines.append(text) }
                isFirstContentLine = false
                continue
            }

            let text = clean(trimmed)
            guard !text.isEmpty else { continue }

            // Setext 見出し: 次の行が === / --- なら、この行が見出し
            if isFirstContentLine, let next = iterator.next() {
                let underline = next.trimmingCharacters(in: .whitespaces)
                if isSetextUnderline(underline) {
                    title = text
                    isFirstContentLine = false
                    continue
                }
                pending = next
            }

            if title == nil, isFirstContentLine { title = text } else { lines.append(text) }
            isFirstContentLine = false
        }

        return ThumbnailSummary(title: title, lines: lines)
    }

    // MARK: - Reading

    /// Lines after any YAML front matter, and never more than it takes to fill a
    /// thumbnail — a 10MB note shouldn't be walked end to end for one icon.
    private static func body(of markdown: String) -> [String] {
        var lines = markdown.split(separator: "\n", maxSplits: 400, omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return lines }
        lines.removeFirst(end + 1)
        return lines
    }

    // MARK: - Flattening

    private static func clean(_ text: String) -> String {
        var result = text

        // 箇条書き・引用・タスクの印を落とす
        result = replacing(result, pattern: "^\\s*(?:[-*+]|\\d+[.)])\\s+(?:\\[[ xX]\\]\\s*)?", with: "")
        result = replacing(result, pattern: "^\\s*>+\\s*", with: "")
        // [text](url) → text、![alt](url) → alt
        result = replacing(result, pattern: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1")
        // 強調・取り消し線・コードの記号
        result = replacing(result, pattern: "(\\*\\*|__|~~|`|\\*|_)", with: "")
        result = replacing(result, pattern: "\\s+", with: " ")
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                              withTemplate: template)
    }

    private static func isRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return ["-", "*", "_"].contains { stripped.allSatisfy(String($0).contains) }
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        return line.allSatisfy { $0 == "=" } || line.allSatisfy { $0 == "-" }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.contains("-"), line.hasPrefix("|") || line.contains("|") else { return false }
        return line.allSatisfy { "|-: ".contains($0) }
    }
}
