import Foundation

/// The result of a successful `FuzzyMatch.match`.
public struct FuzzyMatchResult: Sendable, Equatable {
    public let score: Int
    /// Positions (0-based, by `Character` offset) in the candidate that the query matched.
    public let matchedIndexes: [Int]

    public init(score: Int, matchedIndexes: [Int]) {
        self.score = score
        self.matchedIndexes = matchedIndexes
    }
}

/// Subsequence-based fuzzy matching for Quick Open, plus ranking of recent documents.
public enum FuzzyMatch {
    private enum Score {
        static let base = 1
        static let contiguousBonus = 8
        static let wordBoundaryBonus = 12
        /// Subtracted per character of distance from the start of the candidate, capped so a
        /// match deep into a long string doesn't go negative and dominate the contiguity/boundary signal.
        static let startProximityMax = 10
    }

    /// Characters that mark the start of a new "word" within a file name/path when the
    /// character right before them is different — used for the word-boundary bonus.
    private static func isSeparator(_ c: Character) -> Bool {
        c == "/" || c == "_" || c == "-" || c == " " || c == "."
    }

    /// Whether `candidate[index]` sits at a word boundary: the very first character, right
    /// after a separator, or a lowercase→uppercase transition (camelCase boundary).
    private static func isWordBoundary(_ candidate: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = candidate[index - 1]
        if isSeparator(previous) { return true }
        let current = candidate[index]
        if previous.isLowercase && current.isUppercase { return true }
        return false
    }

    /// Whether `query` is a case-insensitive subsequence of `candidate`. When it is, returns a
    /// score (higher = better) and the matched character positions in `candidate`.
    public static func match(query: String, candidate: String) -> FuzzyMatchResult? {
        if query.isEmpty {
            return FuzzyMatchResult(score: 0, matchedIndexes: [])
        }

        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate)
        let candidateLower = candidateChars.map { Character($0.lowercased()) }

        var matchedIndexes: [Int] = []
        matchedIndexes.reserveCapacity(queryChars.count)
        var score = 0
        var queryIndex = 0
        var previousMatchIndex: Int?

        for candidateIndex in 0..<candidateLower.count {
            guard queryIndex < queryChars.count else { break }
            guard candidateLower[candidateIndex] == queryChars[queryIndex] else { continue }

            matchedIndexes.append(candidateIndex)
            score += Score.base

            if let previous = previousMatchIndex, candidateIndex == previous + 1 {
                score += Score.contiguousBonus
            }
            if isWordBoundary(candidateChars, at: candidateIndex) {
                score += Score.wordBoundaryBonus
            }

            previousMatchIndex = candidateIndex
            queryIndex += 1
        }

        guard queryIndex == queryChars.count else { return nil }

        let startDistance = matchedIndexes.first ?? 0
        score += max(0, Score.startProximityMax - startDistance)

        return FuzzyMatchResult(score: score, matchedIndexes: matchedIndexes)
    }

    /// Ranks `items` for `query`: matches against the file name first, falling back to the
    /// full path when the name alone doesn't match. Non-matches are dropped. Sort is by score
    /// descending, stable (ties keep the original — newest-first — order).
    public static func rank(query: String, items: [RecentDocument]) -> [RecentDocument] {
        if query.isEmpty { return items }

        let scored: [(item: RecentDocument, originalIndex: Int, score: Int)] = items.enumerated().compactMap { index, item in
            let name = item.url.lastPathComponent
            if let nameMatch = match(query: query, candidate: name) {
                return (item, index, nameMatch.score)
            }
            if let pathMatch = match(query: query, candidate: item.url.path) {
                return (item, index, pathMatch.score)
            }
            return nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.originalIndex < rhs.originalIndex
            }
            .map(\.item)
    }
}
