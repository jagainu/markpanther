import XCTest
@testable import MarkPantherCore

final class CanonicalPathTests: XCTestCase {
    func test_equivalentPathsAgree() {
        XCTAssertEqual(CanonicalPath.of("/tmp/./a/../note.md"), CanonicalPath.of("/tmp/note.md"))
    }

    func test_resolvesSymlinkedPrefixes() {
        // /tmp is a symlink to /private/tmp on macOS; both spellings must agree.
        XCTAssertEqual(CanonicalPath.of("/tmp"), CanonicalPath.of("/private/tmp"))
    }

    func test_urlAndStringOverloadsAgree() {
        let url = URL(fileURLWithPath: "/tmp/sample.md")
        XCTAssertEqual(CanonicalPath.of(url), CanonicalPath.of("/tmp/sample.md"))
    }

    func test_missingFileStillNormalizes() {
        let path = CanonicalPath.of("/tmp/definitely-absent-\(UUID().uuidString)/deep/./file.md")
        XCTAssertFalse(path.contains("/./"))
        XCTAssertTrue(path.hasSuffix("/deep/file.md"))
    }

    func test_trailingSlashDoesNotChangeIdentity() {
        XCTAssertEqual(CanonicalPath.of("/tmp/"), CanonicalPath.of("/tmp"))
    }
}
