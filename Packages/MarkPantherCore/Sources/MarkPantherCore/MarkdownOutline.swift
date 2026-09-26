import Foundation

public struct OutlineItem: Equatable, Sendable {
    public var level: Int     // 1...6
    public var title: String  // インライン記法を外した表示用の文字列
    public var line: Int      // 0 始まりのソース行（プレビューの data-line と同じ基準）

    public init(level: Int, title: String, line: Int) {
        self.level = level
        self.title = title
        self.line = line
    }
}

/// 見出しだけを拾う軽量スキャナ。エディタ・プレビューどちらのモードでも同じアウトラインを出すため、
/// プレビューの DOM ではなくソースから作る。
public enum MarkdownOutline {
    public static func parse(_ text: String) -> [OutlineItem] {
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var items: [OutlineItem] = []
        var index = frontmatterEnd(lines)
        var fence: (marker: Character, count: Int)?
        var previousText: (title: String, line: Int)?  // setext 見出しの候補（直前の段落行）

        while index < lines.count {
            let line = lines[index]
            defer { index += 1 }

            if let open = fence {
                if isFenceClose(line, open) { fence = nil }
                continue
            }
            if let open = fenceOpen(line) {
                fence = open
                previousText = nil
                continue
            }
            if let (level, title) = atxHeading(line) {
                if !title.isEmpty { items.append(OutlineItem(level: level, title: title, line: index)) }
                previousText = nil
                continue
            }
            if let candidate = previousText, let level = setextLevel(line) {
                items.append(OutlineItem(level: level, title: candidate.title, line: candidate.line))
                previousText = nil
                continue
            }
            previousText = paragraphLine(line).map { (plainTitle($0), index) }
        }
        return items
    }

    public static func filter(_ items: [OutlineItem], query: String) -> [OutlineItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return items }
        return items.filter { $0.title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    // MARK: - Line classification

    private static func frontmatterEnd(_ lines: [String]) -> Int {
        guard lines.first == "---" else { return 0 }
        for (offset, line) in lines.dropFirst().enumerated() where line == "---" || line == "..." {
            return offset + 2
        }
        return 0
    }

    private static func indentation(_ line: String) -> (spaces: Int, rest: Substring) {
        let rest = line.drop { $0 == " " }
        return (line.count - rest.count, rest)
    }

    private static func fenceOpen(_ line: String) -> (marker: Character, count: Int)? {
        let (spaces, rest) = indentation(line)
        guard spaces <= 3, let marker = rest.first, marker == "`" || marker == "~" else { return nil }
        let count = rest.prefix { $0 == marker }.count
        guard count >= 3 else { return nil }
        if marker == "`", rest.dropFirst(count).contains("`") { return nil }
        return (marker, count)
    }

    private static func isFenceClose(_ line: String, _ open: (marker: Character, count: Int)) -> Bool {
        let (spaces, rest) = indentation(line)
        guard spaces <= 3 else { return false }
        let run = rest.prefix { $0 == open.marker }.count
        return run >= open.count && rest.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func atxHeading(_ line: String) -> (Int, String)? {
        let (spaces, rest) = indentation(line)
        guard spaces <= 3 else { return nil }
        let level = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(level) else { return nil }
        let body = rest.dropFirst(level)
        guard body.isEmpty || body.first == " " || body.first == "\t" else { return nil }

        var title = body.trimmingCharacters(in: .whitespaces)
        // 閉じの `##` は、前が空白（または全体が # だけ）のときだけ外す
        let trailing = title.reversed().prefix { $0 == "#" }.count
        if trailing > 0 {
            let head = title.dropLast(trailing)
            if head.isEmpty || head.last == " " { title = head.trimmingCharacters(in: .whitespaces) }
        }
        return (level, plainTitle(title))
    }

    private static func setextLevel(_ line: String) -> Int? {
        let (spaces, rest) = indentation(line)
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard spaces <= 3, let marker = trimmed.first, marker == "=" || marker == "-",
              trimmed.allSatisfy({ $0 == marker }) else { return nil }
        return marker == "=" ? 1 : 2
    }

    /// setext 見出しの本文になり得る、素の段落行だけを返す。
    private static func paragraphLine(_ line: String) -> String? {
        let (spaces, rest) = indentation(line)
        let trimmed = rest.trimmingCharacters(in: .whitespaces)
        guard spaces <= 3, let first = trimmed.first else { return nil }
        if first == ">" || first == "|" || first == "<" { return nil }
        if trimmed.range(of: #"^([-*+]|\d{1,9}[.)])(\s|$)"#, options: .regularExpression) != nil { return nil }
        return trimmed
    }

    // MARK: - Title cleanup

    private static let titleRules: [(pattern: String, template: String)] = [
        (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),          // 画像
        (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),           // インラインリンク
        (#"\[([^\]]+)\]\[[^\]]*\]"#, "$1"),          // 参照リンク
        (#"`+([^`]+)`+"#, "$1"),                     // インラインコード
        (#"(\*\*|__)(.+?)\1"#, "$2"),                // strong
        (#"(?<![\w*])([*_])(.+?)\1(?![\w*])"#, "$2"), // emphasis
        (#"(~~|==)(.+?)\1"#, "$2"),                  // 打ち消し・ハイライト
        (#"<[^>]+>"#, ""),                           // 生 HTML タグ
    ]

    private static func plainTitle(_ raw: String) -> String {
        var title = raw
        for rule in titleRules {
            title = title.replacingOccurrences(of: rule.pattern, with: rule.template, options: .regularExpression)
        }
        return title.trimmingCharacters(in: .whitespaces)
    }
}
