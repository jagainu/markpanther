import XCTest
@testable import MarkPantherCore

final class DockMenuModelTests: XCTestCase {
    private func recent(_ path: String, _ secondsAgo: TimeInterval = 0) -> RecentDocument {
        RecentDocument(url: URL(fileURLWithPath: path), opened: Date(timeIntervalSince1970: 10_000 - secondsAgo))
    }

    func testOpenWindowsComeFirst() {
        let entries = DockMenuModel.entries(
            recents: [recent("/w/README.md"), recent("/w/notes.md", 10)],
            open: [URL(fileURLWithPath: "/w/notes.md")]
        )

        XCTAssertEqual(entries.first, .open(title: "notes.md", path: "/w/notes.md"))
    }

    func testAnOpenDocumentIsNotRepeatedUnderRecent() {
        let entries = DockMenuModel.entries(
            recents: [recent("/w/README.md"), recent("/w/notes.md", 10)],
            open: [URL(fileURLWithPath: "/w/notes.md")]
        )

        XCTAssertEqual(entries.filter { $0.path == "/w/notes.md" }.count, 1)
        XCTAssertTrue(entries.contains(.recent(title: "README.md", path: "/w/README.md")))
    }

    func testMatchesAnOpenDocumentThroughSymlinksAndDotSegments() {
        let entries = DockMenuModel.entries(
            recents: [recent("/w/./notes.md")],
            open: [URL(fileURLWithPath: "/w/notes.md")]
        )

        XCTAssertEqual(entries.filter { $0.path != nil }.count, 1)
    }

    func testRecentsAreCappedAndKeepTheirOrder() {
        let recents = (0..<12).map { recent("/w/doc\($0).md", TimeInterval($0)) }
        let entries = DockMenuModel.entries(recents: recents, open: [], limit: 4)

        let titles = entries.compactMap { entry -> String? in
            if case .recent(let title, _) = entry { return title }
            return nil
        }
        XCTAssertEqual(titles, ["doc0.md", "doc1.md", "doc2.md", "doc3.md"])
    }

    func testTheLimitCountsOnlyRecentsNotOpenWindows() {
        let recents = (0..<6).map { recent("/w/doc\($0).md", TimeInterval($0)) }
        let entries = DockMenuModel.entries(
            recents: recents,
            open: [URL(fileURLWithPath: "/w/doc0.md")],
            limit: 3
        )

        XCTAssertEqual(entries.filter { if case .recent = $0 { return true } else { return false } }.count, 3)
        XCTAssertEqual(entries.filter { if case .open = $0 { return true } else { return false } }.count, 1)
    }

    func testSectionsAreSeparatedButNeverWithALeadingOrDoubledRule() {
        let entries = DockMenuModel.entries(
            recents: [recent("/w/README.md")],
            open: [URL(fileURLWithPath: "/w/notes.md")]
        )

        XCTAssertNotEqual(entries.first, .separator)
        XCTAssertNotEqual(entries.last, .separator)
        for (a, b) in zip(entries, entries.dropFirst()) {
            XCTAssertFalse(a == .separator && b == .separator, "区切り線が連続している")
        }
    }

    func testNothingOpenAndNothingRecentGivesJustTheNewItem() {
        XCTAssertEqual(DockMenuModel.entries(recents: [], open: []), [.newDocument])
    }

    func testNewDocumentIsAlwaysLast() {
        let entries = DockMenuModel.entries(
            recents: [recent("/w/README.md")],
            open: [URL(fileURLWithPath: "/w/notes.md")]
        )

        XCTAssertEqual(entries.last, .newDocument)
    }
}
