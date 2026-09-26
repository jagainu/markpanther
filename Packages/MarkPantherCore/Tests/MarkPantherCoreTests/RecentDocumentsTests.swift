import XCTest
@testable import MarkPantherCore

final class RecentDocumentsTests: XCTestCase {
    /// Same key `RecentDocuments` stores its list under, duplicated here so the
    /// "corrupt data" test can inject garbage without needing production code to expose it.
    private static let storageKey = "MarkPantherCore.recentDocuments"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDirs: [URL] = []

    override func setUpWithError() throws {
        suiteName = "RecentDocumentsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
    }

    private func makeTempFile(name: String = "doc.md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentDocumentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        let url = dir.appendingPathComponent(name)
        try "content".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecentDocumentsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    // MARK: - Ordering

    func test_items_returnsNewestFirst() throws {
        let recents = RecentDocuments(defaults: defaults)
        let a = try makeTempFile(name: "a.md")
        let b = try makeTempFile(name: "b.md")
        let c = try makeTempFile(name: "c.md")

        recents.record(a)
        recents.record(b)
        recents.record(c)

        XCTAssertEqual(recents.items().map(\.url), [c, b, a])
    }

    // MARK: - Dedupe

    func test_record_sameFileAgain_movesToFrontWithoutDuplicating() throws {
        let recents = RecentDocuments(defaults: defaults)
        let a = try makeTempFile(name: "a.md")
        let b = try makeTempFile(name: "b.md")

        recents.record(a)
        recents.record(b)
        recents.record(a)

        let items = recents.items()
        XCTAssertEqual(items.map(\.url), [a, b])
    }

    // MARK: - Limit

    func test_record_overLimit_dropsOldest() throws {
        let recents = RecentDocuments(defaults: defaults, limit: 2)
        let a = try makeTempFile(name: "a.md")
        let b = try makeTempFile(name: "b.md")
        let c = try makeTempFile(name: "c.md")

        recents.record(a)
        recents.record(b)
        recents.record(c)

        XCTAssertEqual(recents.items().map(\.url), [c, b])
    }

    // MARK: - Missing files

    func test_items_excludesMissingFilesAndPersistsRemoval() throws {
        let recents = RecentDocuments(defaults: defaults)
        let a = try makeTempFile(name: "a.md")
        let b = try makeTempFile(name: "b.md")

        recents.record(a)
        recents.record(b)
        try FileManager.default.removeItem(at: a)

        XCTAssertEqual(recents.items().map(\.url), [b])

        // Removal of the missing entry should have been persisted, so a fresh
        // instance backed by the same defaults never sees it again either.
        let reopened = RecentDocuments(defaults: defaults)
        XCTAssertEqual(reopened.items().map(\.url), [b])
    }

    // MARK: - Corrupt data

    func test_items_withCorruptStoredData_returnsEmpty() throws {
        defaults.set("not valid json".data(using: .utf8), forKey: Self.storageKey)
        let recents = RecentDocuments(defaults: defaults)
        XCTAssertEqual(recents.items(), [])
    }

    // MARK: - Shared suite

    func test_separateInstance_sameSuite_readsBackRecordedDocuments() throws {
        let first = RecentDocuments(defaults: defaults)
        let a = try makeTempFile(name: "a.md")
        first.record(a)

        let second = RecentDocuments(defaults: defaults)
        XCTAssertEqual(second.items().map(\.url), [a])
    }

    // MARK: - Clear

    func test_clear_removesAllEntries() throws {
        let recents = RecentDocuments(defaults: defaults)
        let a = try makeTempFile(name: "a.md")
        recents.record(a)
        XCTAssertFalse(recents.items().isEmpty)

        recents.clear()

        XCTAssertTrue(recents.items().isEmpty)
    }
}
