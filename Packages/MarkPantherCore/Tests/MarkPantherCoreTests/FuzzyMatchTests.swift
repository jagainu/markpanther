import XCTest
@testable import MarkPantherCore

final class FuzzyMatchTests: XCTestCase {
    // MARK: - Basic subsequence matching

    func test_match_subsequencePresent_matches() {
        XCTAssertNotNil(FuzzyMatch.match(query: "tod", candidate: "todo.md"))
        XCTAssertNotNil(FuzzyMatch.match(query: "tdmd", candidate: "todo.md"))
    }

    func test_match_subsequenceAbsent_returnsNil() {
        XCTAssertNil(FuzzyMatch.match(query: "xyz", candidate: "todo.md"))
        XCTAssertNil(FuzzyMatch.match(query: "dot", candidate: "todo.md"))
    }

    // MARK: - Case insensitivity

    func test_match_isCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatch.match(query: "TOD", candidate: "todo.md"))
        XCTAssertNotNil(FuzzyMatch.match(query: "tod", candidate: "TODO.MD"))
    }

    // MARK: - Scoring: contiguity

    func test_match_contiguousMatch_scoresHigherThanScattered() {
        let contiguous = FuzzyMatch.match(query: "tod", candidate: "todo.md")!
        // Filler digits avoid separators/case-transitions so this is scattered *without*
        // also picking up word-boundary bonuses that would confound the comparison.
        let scattered = FuzzyMatch.match(query: "tod", candidate: "t11o11d11file.md")!
        XCTAssertGreaterThan(contiguous.score, scattered.score)
    }

    // MARK: - Scoring: word boundaries

    func test_match_wordBoundaryMatch_scoresHigherThanMidWord() {
        // "rn" matches "ReadMe" at word/case boundaries (R, M) vs "warren.md" mid-word.
        let boundary = FuzzyMatch.match(query: "rm", candidate: "ReadMe.md")!
        let midWord = FuzzyMatch.match(query: "rm", candidate: "warren-model.md")!
        XCTAssertGreaterThan(boundary.score, midWord.score)
    }

    func test_match_separatorBoundary_scoresHigherThanMidWord() {
        let afterSeparator = FuzzyMatch.match(query: "not", candidate: "my_notes.md")!
        let midWord = FuzzyMatch.match(query: "not", candidate: "annotation.md")!
        XCTAssertGreaterThan(afterSeparator.score, midWord.score)
    }

    // MARK: - Scoring: proximity to start

    func test_match_matchNearStart_scoresHigherThanMatchFurtherIn() {
        let nearStart = FuzzyMatch.match(query: "abc", candidate: "abc-file.md")!
        let laterIn = FuzzyMatch.match(query: "abc", candidate: "xxxxxxxxabc-file.md")!
        XCTAssertGreaterThan(nearStart.score, laterIn.score)
    }

    // MARK: - Empty query

    func test_match_emptyQuery_matchesAllWithZeroScoreAndNoIndexes() {
        let result = FuzzyMatch.match(query: "", candidate: "anything.md")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.score, 0)
        XCTAssertEqual(result?.matchedIndexes, [])
    }

    // MARK: - matchedIndexes correctness

    func test_match_matchedIndexes_pointToCorrectPositions() {
        let result = FuzzyMatch.match(query: "tdm", candidate: "todo.md")!
        XCTAssertEqual(result.matchedIndexes, [0, 2, 5])
        for index in result.matchedIndexes {
            let candidate = "todo.md"
            let char = candidate[candidate.index(candidate.startIndex, offsetBy: index)]
            XCTAssertTrue("tdm".lowercased().contains(char.lowercased()))
        }
    }

    // MARK: - rank

    func test_rank_ordersByScoreDescending() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/tmp/x-something-todo.md"), opened: now),
            RecentDocument(url: URL(fileURLWithPath: "/tmp/todo.md"), opened: now),
        ]
        let ranked = FuzzyMatch.rank(query: "todo", items: items)
        XCTAssertEqual(ranked.map { $0.url.lastPathComponent }, ["todo.md", "x-something-todo.md"])
    }

    func test_rank_tiedScore_preservesOriginalOrder() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/tmp/a/notes.md"), opened: now),
            RecentDocument(url: URL(fileURLWithPath: "/tmp/b/notes.md"), opened: now),
        ]
        let ranked = FuzzyMatch.rank(query: "notes", items: items)
        XCTAssertEqual(ranked.map(\.url), items.map(\.url))
    }

    func test_rank_emptyQuery_returnsAllInOriginalOrder() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/tmp/a.md"), opened: now),
            RecentDocument(url: URL(fileURLWithPath: "/tmp/b.md"), opened: now),
            RecentDocument(url: URL(fileURLWithPath: "/tmp/c.md"), opened: now),
        ]
        let ranked = FuzzyMatch.rank(query: "", items: items)
        XCTAssertEqual(ranked.map(\.url), items.map(\.url))
    }

    func test_rank_filtersOutNonMatches() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/tmp/todo.md"), opened: now),
            RecentDocument(url: URL(fileURLWithPath: "/tmp/readme.md"), opened: now),
        ]
        let ranked = FuzzyMatch.rank(query: "zzz", items: items)
        XCTAssertTrue(ranked.isEmpty)
    }

    // MARK: - rank: filename-first, falls back to full path

    func test_rank_matchesOnFileNameFirst() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/Users/mak/projects/notes.md"), opened: now),
        ]
        let ranked = FuzzyMatch.rank(query: "notes", items: items)
        XCTAssertEqual(ranked.count, 1)
    }

    func test_rank_fallsBackToFullPathWhenFileNameDoesNotMatch() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/Users/mak/markpanther/todo.md"), opened: now),
        ]
        // "markp" only appears in the path, not in the file name "todo.md".
        let ranked = FuzzyMatch.rank(query: "markp", items: items)
        XCTAssertEqual(ranked.count, 1)
    }

    func test_rank_noMatchInNameOrPath_isExcluded() {
        let now = Date()
        let items = [
            RecentDocument(url: URL(fileURLWithPath: "/Users/mak/markpanther/todo.md"), opened: now),
        ]
        let ranked = FuzzyMatch.rank(query: "zzzzz", items: items)
        XCTAssertTrue(ranked.isEmpty)
    }
}
