import XCTest
@testable import MarkPantherCore

final class PathBreadcrumbTests: XCTestCase {
    private func names(_ urls: [URL]) -> [String] {
        urls.map { $0.path == "/" ? "/" : $0.lastPathComponent }
    }

    func test_walksFromFileUpToRoot() {
        let components = PathBreadcrumb.components(of: URL(fileURLWithPath: "/private/tmp/demo/notes.md"))
        XCTAssertEqual(names(components), ["notes.md", "demo", "tmp", "/"])
    }

    func test_rootIsASingleComponent() {
        XCTAssertEqual(names(PathBreadcrumb.components(of: URL(fileURLWithPath: "/"))), ["/"])
    }

    func test_fileSchemeURLBehavesLikeAPath() {
        let url = try! XCTUnwrap(URL(string: "file:///private/tmp/demo/notes.md"))
        XCTAssertEqual(names(PathBreadcrumb.components(of: url)), ["notes.md", "demo", "tmp", "/"])
    }

    /// A relative URL used to spin forever: `deletingLastPathComponent()` keeps
    /// prepending `../`, so a path-equality guard never fires.
    func test_relativeURLTerminates() {
        let url = try! XCTUnwrap(URL(string: "notes.md"))
        let components = PathBreadcrumb.components(of: url)
        XCTAssertFalse(components.isEmpty)
        XCTAssertEqual(components.last?.path, "/")
        XCTAssertEqual(components.first?.lastPathComponent, "notes.md")
        XCTAssertFalse(components.contains { $0.path.contains("..") })
    }

    func test_dotSegmentsAreResolved() {
        let components = PathBreadcrumb.components(of: URL(fileURLWithPath: "/private/tmp/./demo/../demo/notes.md"))
        XCTAssertEqual(names(components), ["notes.md", "demo", "tmp", "/"])
    }

    func test_handlesSpacesAndNonASCIINames() {
        let components = PathBreadcrumb.components(of: URL(fileURLWithPath: "/private/tmp/デモ フォルダ/メモ.md"))
        XCTAssertEqual(names(components), ["メモ.md", "デモ フォルダ", "tmp", "/"])
    }

    func test_everyStepIsStrictlyCloserToRoot() {
        let components = PathBreadcrumb.components(of: URL(fileURLWithPath: "/a/b/c/d/e.md"))
        let counts = components.map(\.pathComponents.count)
        XCTAssertEqual(counts, counts.sorted(by: >), "each step must move up, or the walk cannot terminate")
        XCTAssertEqual(Set(counts).count, counts.count)
    }
}
