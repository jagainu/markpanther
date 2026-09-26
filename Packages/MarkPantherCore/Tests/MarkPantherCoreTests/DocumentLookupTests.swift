import XCTest
@testable import MarkPantherCore

final class DocumentLookupTests: XCTestCase {
    private func recent(_ path: String, _ secondsAgo: TimeInterval = 0) -> RecentDocument {
        RecentDocument(url: URL(fileURLWithPath: path), opened: Date(timeIntervalSince1970: 10_000 - secondsAgo))
    }

    private func project(_ path: String, _ relative: String) -> ProjectFile {
        ProjectFile(url: URL(fileURLWithPath: path), relativePath: relative,
                    modified: Date(timeIntervalSince1970: 9_000))
    }

    private func find(_ query: String, recents: [RecentDocument] = [], project files: [ProjectFile] = [],
                      limit: Int = 12) -> [String] {
        DocumentLookup.find(query: query, recents: recents, project: files, limit: limit)
            .map(\.url.lastPathComponent)
    }

    func testFindsAFileByItsNameWithoutTheExtension() {
        let found = find("README", recents: [recent("/w/README.md"), recent("/w/notes.md")])
        XCTAssertEqual(found.first, "README.md")
    }

    func testAnExactNameOutranksAScatteredMatch() {
        // "notes" は spec-notes-draft.md にも散らばって含まれる
        let found = find("notes", recents: [recent("/w/spec-notes-draft.md"), recent("/w/notes.md")])
        XCTAssertEqual(found.first, "notes.md")
    }

    func testSearchesProjectFilesToo() {
        let found = find("plan", project: [project("/w/docs/plan.md", "docs/plan.md")])
        XCTAssertEqual(found, ["plan.md"])
    }

    func testTheSameFileFromBothSourcesAppearsOnce() {
        let found = find("notes",
                         recents: [recent("/w/notes.md")],
                         project: [project("/w/notes.md", "notes.md")])
        XCTAssertEqual(found, ["notes.md"])
    }

    func testMatchesAcrossSymlinksAndDotSegmentsWhenDeduplicating() {
        let found = find("notes",
                         recents: [recent("/w/notes.md")],
                         project: [project("/w/./notes.md", "notes.md")])
        XCTAssertEqual(found.count, 1)
    }

    func testRecentlyOpenedFilesComeBeforeMereProjectFiles() {
        // 同じ名前で同じスコアなら、開いたことのあるほうを先に出す
        let found = DocumentLookup.find(
            query: "notes",
            recents: [recent("/a/notes.md")],
            project: [project("/b/notes.md", "notes.md")]
        )
        XCTAssertEqual(found.map(\.url.path), ["/a/notes.md", "/b/notes.md"])
    }

    func testAnEmptyQueryReturnsEverythingNewestFirst() {
        let found = find("", recents: [recent("/w/a.md"), recent("/w/b.md", 10)])
        XCTAssertEqual(found, ["a.md", "b.md"])
    }

    func testTheLimitApplies() {
        let recents = (0..<20).map { recent("/w/doc\($0).md", TimeInterval($0)) }
        XCTAssertEqual(find("", recents: recents, limit: 5).count, 5)
    }

    func testAQueryThatMatchesNothingReturnsNothing() {
        XCTAssertTrue(find("zzz", recents: [recent("/w/notes.md")]).isEmpty)
    }

    func testCanSearchByPathWhenTheNameAloneDoesNotMatch() {
        let found = find("docsplan", project: [project("/w/docs/plan.md", "docs/plan.md")])
        XCTAssertEqual(found, ["plan.md"])
    }
}
