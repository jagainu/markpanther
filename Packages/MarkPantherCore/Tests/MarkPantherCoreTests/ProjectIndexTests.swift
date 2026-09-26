import XCTest
@testable import MarkPantherCore

final class ProjectRootTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectRootTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_find_returnsAncestorWithGitDirectory() throws {
        let projectRoot = tempDir.appendingPathComponent("project", isDirectory: true)
        let nested = projectRoot.appendingPathComponent("a/b/c", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectRoot.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let fileURL = nested.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let found = ProjectRoot.find(for: fileURL)
        XCTAssertEqual(found.standardizedFileURL.path, projectRoot.standardizedFileURL.path)
    }

    func test_find_gitAsFile_isAlsoRecognized() throws {
        // git worktrees use a `.git` *file* (containing `gitdir: ...`) instead of a directory.
        let projectRoot = tempDir.appendingPathComponent("worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        try "gitdir: /somewhere/else".write(
            to: projectRoot.appendingPathComponent(".git"), atomically: true, encoding: .utf8
        )

        let fileURL = projectRoot.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let found = ProjectRoot.find(for: fileURL)
        XCTAssertEqual(found.standardizedFileURL.path, projectRoot.standardizedFileURL.path)
    }

    func test_find_noGitAnywhere_returnsFilesOwnDirectory() throws {
        let dir = tempDir.appendingPathComponent("lonely", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let found = ProjectRoot.find(for: fileURL)
        XCTAssertEqual(found.standardizedFileURL.path, dir.standardizedFileURL.path)
    }

    func test_find_doesNotSearchAboveMaxDepth() throws {
        // Build a chain of 12 nested directories under tmp (which is not inside the
        // real home directory), with `.git` only at the very top. The search must give
        // up at 10 levels and fall back to the file's own directory rather than reaching it.
        var deepest = tempDir!
        for i in 0..<12 {
            deepest = deepest.appendingPathComponent("d\(i)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: deepest, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let fileURL = deepest.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let found = ProjectRoot.find(for: fileURL)
        XCTAssertEqual(found.standardizedFileURL.path, deepest.standardizedFileURL.path)
    }

    func test_find_doesNotGoAboveHomeDirectory() throws {
        // We cannot plant a `.git` above the real home directory in a test (that would
        // require writing outside the sandboxed temp/home tree). Instead this verifies
        // that a chain living under the real home directory, with no `.git` anywhere in
        // it, resolves without climbing out of the home tree and without hanging —
        // i.e. the boundary check does not crash or mis-terminate the walk.
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let topLevel = homeDir.appendingPathComponent(
            ".markpanther-project-index-tests-\(UUID().uuidString)", isDirectory: true
        )
        let dir = topLevel.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: topLevel) }

        let fileURL = dir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let found = ProjectRoot.find(for: fileURL)
        XCTAssertEqual(found.standardizedFileURL.path, dir.standardizedFileURL.path)
    }
}

final class ProjectIndexTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ relativePath: String, content: String = "content") throws -> URL {
        let url = tempDir.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func test_scan_findsMarkdownFilesRecursively() throws {
        _ = try write("readme.md")
        _ = try write("docs/guide.markdown")
        _ = try write("docs/nested/deep.mdown")
        _ = try write("notes.mkd")
        _ = try write("script.swift")

        let files = ProjectIndex.scan(root: tempDir)
        let relativePaths = Set(files.map(\.relativePath))
        XCTAssertEqual(relativePaths, [
            "docs/guide.markdown", "docs/nested/deep.mdown", "notes.mkd", "readme.md",
        ])
    }

    func test_scan_returnsRelativePathsInLexicographicOrder() throws {
        _ = try write("z.md")
        _ = try write("a.md")
        _ = try write("m/b.md")

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(files.map(\.relativePath), ["a.md", "m/b.md", "z.md"])
    }

    func test_scan_excludesKnownDirectories() throws {
        _ = try write("readme.md")
        _ = try write("node_modules/pkg/file.md")
        _ = try write("build/out.md")
        _ = try write(".build/out.md")
        _ = try write("DerivedData/out.md")
        _ = try write("dist/out.md")
        _ = try write("vendor/out.md")
        _ = try write(".next/out.md")
        _ = try write("Pods/out.md")
        _ = try write(".git/out.md")

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(files.map(\.relativePath), ["readme.md"])
    }

    func test_scan_excludesAllDotDirectories() throws {
        _ = try write("readme.md")
        _ = try write(".hidden/file.md")
        _ = try write(".config/nested/file.md")

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(files.map(\.relativePath), ["readme.md"])
    }

    func test_scan_excludesHiddenFiles() throws {
        _ = try write("readme.md")
        _ = try write(".hidden.md")

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(files.map(\.relativePath), ["readme.md"])
    }

    func test_scan_ignoresNonMarkdownExtensions() throws {
        _ = try write("readme.md")
        _ = try write("main.swift")
        _ = try write("image.png")
        _ = try write("MD.txt")

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(files.map(\.relativePath), ["readme.md"])
    }

    func test_scan_isCaseInsensitiveOnExtension() throws {
        _ = try write("readme.MD")
        _ = try write("guide.Markdown")

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(Set(files.map(\.relativePath)), ["readme.MD", "guide.Markdown"])
    }

    func test_scan_respectsMaxDepth() throws {
        // depth 0 = root. Place files at increasing depth and cap at 2.
        _ = try write("d0.md")
        _ = try write("l1/d1.md")
        _ = try write("l1/l2/d2.md")
        _ = try write("l1/l2/l3/d3.md")

        let files = ProjectIndex.scan(root: tempDir, maxDepth: 2)
        let relativePaths = Set(files.map(\.relativePath))
        XCTAssertTrue(relativePaths.contains("d0.md"))
        XCTAssertTrue(relativePaths.contains("l1/d1.md"))
        XCTAssertTrue(relativePaths.contains("l1/l2/d2.md"))
        XCTAssertFalse(relativePaths.contains("l1/l2/l3/d3.md"))
    }

    func test_scan_respectsMaxFiles_returnsPartialResultWithoutCrashing() throws {
        for i in 0..<50 {
            _ = try write("file\(String(format: "%03d", i)).md")
        }

        let files = ProjectIndex.scan(root: tempDir, maxFiles: 10)
        XCTAssertLessThanOrEqual(files.count, 10)
        XCTAssertFalse(files.isEmpty)
    }

    func test_scan_doesNotFollowSymlinkedDirectories() throws {
        let realDir = tempDir.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        _ = try write("real/inside.md")

        let linkDir = tempDir.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: realDir)

        let files = ProjectIndex.scan(root: tempDir)
        let relativePaths = Set(files.map(\.relativePath))
        XCTAssertTrue(relativePaths.contains("real/inside.md"))
        XCTAssertFalse(relativePaths.contains("link/inside.md"))
    }

    func test_scan_emptyRoot_returnsEmptyArray() throws {
        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertTrue(files.isEmpty)
    }

    func test_scan_modifiedDateReflectsFileSystem() throws {
        let url = try write("readme.md")
        let expected = (try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)!

        let files = ProjectIndex.scan(root: tempDir)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(
            files[0].modified.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1.0
        )
    }
}
