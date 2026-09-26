import Foundation

/// ステータスバー用の統計。トークン数はトークナイザを持たない概算
/// （ASCII は約 4 文字で 1 トークン、和文などそれ以外は 1 文字 1 トークン）で、表示には必ず「~」を付ける。
public struct TextStats: Equatable, Sendable {
    public let words: Int
    public let characters: Int
    public let approximateTokens: Int
    public let readingMinutes: Int

    public init(_ text: String) {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        var ascii = 0
        var wide = 0
        var visible = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if scalar.isASCII { ascii += 1 }
                continue
            }
            visible += 1
            if scalar.isASCII { ascii += 1 } else { wide += 1 }
        }
        self.words = words
        characters = text.count
        approximateTokens = visible == 0 ? 0 : Int((Double(ascii) / 4).rounded()) + wide

        // 英文は 230 語/分、和文は 500 文字/分。和文の語数は形態素単位で数えられてしまうので文字数で見る
        let asciiWords = Double(ascii) / 5.5
        let minutes = asciiWords / 230 + Double(wide) / 500
        readingMinutes = visible == 0 ? 0 : max(1, Int(minutes.rounded()))
    }

    public static func formatTokens(_ tokens: Int) -> String {
        switch tokens {
        case 0: return "0 tokens"
        case ..<1000: return "~\(tokens) tokens"
        case ..<10_000: return "~\(String(format: "%.1f", Double(tokens) / 1000))K tokens"
        default: return "~\(tokens / 1000)K tokens"
        }
    }
}
