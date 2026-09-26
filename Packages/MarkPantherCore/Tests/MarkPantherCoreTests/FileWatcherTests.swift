import XCTest
@testable import MarkPantherCore

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class FileWatcherTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testDetectsNormalOverwrite() throws {
        let fileURL = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let changed = expectation(description: "change detected")
        let watcher = FileWatcher(url: fileURL) {
            changed.fulfill()
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.3)

        try "hello world".write(to: fileURL, atomically: false, encoding: .utf8)

        wait(for: [changed], timeout: 5)
        watcher.stop()
    }

    func testDetectsAtomicReplace() throws {
        let fileURL = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let changed = expectation(description: "atomic replace detected")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(url: fileURL) {
            changed.fulfill()
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.3)

        // Data.write(options: .atomic) writes to a temp sibling then renames over target.
        try "hello atomic".data(using: .utf8)!.write(to: fileURL, options: .atomic)

        wait(for: [changed], timeout: 5)
        watcher.stop()
    }

    func testDetectsDeleteThenRecreate() throws {
        let fileURL = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let changed = expectation(description: "delete+recreate detected")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(url: fileURL) {
            changed.fulfill()
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.3)

        try FileManager.default.removeItem(at: fileURL)
        try "recreated".write(to: fileURL, atomically: true, encoding: .utf8)

        wait(for: [changed], timeout: 5)
        watcher.stop()
    }

    func testIgnoresUnrelatedFileInSameDirectory() throws {
        let fileURL = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let otherURL = tempDir.appendingPathComponent("other.md")

        // FSEvents' "since now" cutoff is not perfectly precise: an atomic write's
        // rename can still be reported shortly after a stream starts if the stream
        // is created too soon after that write. Let the setup write's event settle
        // before starting the watcher, so it doesn't produce a spurious self-match
        // that would be mistaken for a reaction to `otherURL` below.
        Thread.sleep(forTimeInterval: 1.0)

        let unexpected = expectation(description: "should not fire")
        unexpected.isInverted = true
        let watcher = FileWatcher(url: fileURL) {
            unexpected.fulfill()
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.3)

        try "other content".write(to: otherURL, atomically: true, encoding: .utf8)

        wait(for: [unexpected], timeout: 1.5)
        watcher.stop()
    }

    func testStopPreventsFurtherNotifications() throws {
        let fileURL = tempDir.appendingPathComponent("note.md")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let counter = Counter()
        let firstChange = expectation(description: "first change")
        firstChange.assertForOverFulfill = false
        let watcher = FileWatcher(url: fileURL) {
            let newCount = counter.increment()
            if newCount == 1 { firstChange.fulfill() }
        }
        watcher.start()
        Thread.sleep(forTimeInterval: 0.3)

        try "change1".data(using: .utf8)!.write(to: fileURL, options: .atomic)
        wait(for: [firstChange], timeout: 5)

        watcher.stop()

        let noMoreChanges = expectation(description: "no more changes after stop")
        noMoreChanges.isInverted = true
        try "change2".data(using: .utf8)!.write(to: fileURL, options: .atomic)
        wait(for: [noMoreChanges], timeout: 1.5)

        XCTAssertEqual(counter.value, 1)
    }
}
