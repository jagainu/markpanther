import XCTest
@testable import MarkPantherCore

private final class FakeCancellable: SessionCancellable {
    private(set) var cancelled = false
    func cancel() { cancelled = true }
}

@MainActor
private final class FakeScheduler: SessionScheduler, @unchecked Sendable {
    struct Scheduled {
        let delay: TimeInterval
        let work: @MainActor () -> Void
        let cancellable: FakeCancellable
    }

    private(set) var scheduled: [Scheduled] = []

    func schedule(after: TimeInterval, _ work: @escaping @MainActor () -> Void) -> SessionCancellable {
        let cancellable = FakeCancellable()
        scheduled.append(Scheduled(delay: after, work: work, cancellable: cancellable))
        return cancellable
    }

    /// Fires the most recently scheduled work item, as if its delay had elapsed,
    /// unless it was cancelled in the meantime (mirrors real debounce behavior).
    func fireLatest() {
        guard let last = scheduled.last, !last.cancellable.cancelled else { return }
        last.work()
    }
}

@MainActor
final class DocumentSessionTests: XCTestCase {
    nonisolated(unsafe) private var tempDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs = []
    }

    private func makeTempFile(content: String, ext: String = "md") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        let url = dir.appendingPathComponent("doc.\(ext)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    // MARK: - load

    func test_load_setsBufferAndSyncedState() throws {
        let url = try makeTempFile(content: "hello world")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        XCTAssertEqual(session.buffer, "hello world")
        XCTAssertEqual(session.state, .synced)
    }

    func test_load_missingFile_setsMissingState() throws {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("ghost.md")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        XCTAssertEqual(session.state, .missing)
    }

    func test_load_nilFileURL_startsEmptySynced() throws {
        let session = DocumentSession(fileURL: nil, scheduler: FakeScheduler())
        try session.load()
        XCTAssertEqual(session.buffer, "")
        XCTAssertEqual(session.state, .synced)
    }

    // MARK: - userEdited / autosave debounce

    func test_userEdited_marksDirtyAndSchedulesAutosave() throws {
        let url = try makeTempFile(content: "hello")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, autosaveDelay: 0.5, scheduler: scheduler)
        try session.load()

        session.userEdited("hello1")

        XCTAssertEqual(session.state, .dirty)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled[0].delay, 0.5)
    }

    func test_userEdited_rapidEdits_cancelsPreviousTimer() throws {
        let url = try makeTempFile(content: "hello")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()

        session.userEdited("hello1")
        session.userEdited("hello12")

        XCTAssertEqual(scheduler.scheduled.count, 2)
        XCTAssertTrue(scheduler.scheduled[0].cancellable.cancelled)
        XCTAssertFalse(scheduler.scheduled[1].cancellable.cancelled)
    }

    func test_userEdited_debouncedAutosave_writesLatestContent() throws {
        let url = try makeTempFile(content: "hello")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()

        session.userEdited("hello1")
        session.userEdited("hello12")
        scheduler.fireLatest()

        XCTAssertEqual(session.state, .synced)
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(saved, "hello12")
    }

    func test_newDocument_withoutFileURL_doesNotScheduleAutosave() {
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: nil, scheduler: scheduler)
        session.userEdited("draft content")
        XCTAssertEqual(session.state, .dirty)
        XCTAssertEqual(scheduler.scheduled.count, 0)
    }

    // MARK: - flush

    func test_flush_doesNothing_whenNotDirty() throws {
        let url = try makeTempFile(content: "hello")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        session.flush()
        XCTAssertEqual(session.state, .synced)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "hello")
    }

    func test_flush_writesImmediately_cancelingPendingTimer() throws {
        let url = try makeTempFile(content: "hello")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        session.userEdited("hello-edited")

        session.flush()

        XCTAssertEqual(session.state, .synced)
        XCTAssertTrue(scheduler.scheduled.last?.cancellable.cancelled ?? false)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "hello-edited")
    }

    func test_flush_doesNothing_duringConflict() throws {
        let url = try makeTempFile(content: "v1")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        session.userEdited("v1-mine")
        try "v1-external".write(to: url, atomically: true, encoding: .utf8)
        session.fileDidChangeOnDisk()
        XCTAssertEqual(session.state, .conflict)

        session.flush()

        XCTAssertEqual(session.state, .conflict)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "v1-external")
    }

    // MARK: - fileDidChangeOnDisk

    func test_fileDidChangeOnDisk_diskMatchesBuffer_doesNotNotify() throws {
        let url = try makeTempFile(content: "same")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        var notified = false
        session.onExternalUpdate = { _ in notified = true }

        try "same".write(to: url, atomically: true, encoding: .utf8)
        session.fileDidChangeOnDisk()

        XCTAssertFalse(notified)
        XCTAssertEqual(session.state, .synced)
    }

    func test_fileDidChangeOnDisk_cleanBuffer_appliesExternalChange() throws {
        let url = try makeTempFile(content: "orig")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        var received: String?
        session.onExternalUpdate = { received = $0 }

        try "changed-externally".write(to: url, atomically: true, encoding: .utf8)
        session.fileDidChangeOnDisk()

        XCTAssertEqual(session.buffer, "changed-externally")
        XCTAssertEqual(received, "changed-externally")
        XCTAssertEqual(session.state, .synced)
    }

    func test_fileDidChangeOnDisk_dirtyBuffer_setsConflictAndCancelsAutosave() throws {
        let url = try makeTempFile(content: "v1")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        session.userEdited("v1-mine")
        XCTAssertEqual(session.state, .dirty)

        try "v1-external".write(to: url, atomically: true, encoding: .utf8)
        session.fileDidChangeOnDisk()

        XCTAssertEqual(session.state, .conflict)
        XCTAssertEqual(session.buffer, "v1-mine")
        XCTAssertTrue(scheduler.scheduled.last?.cancellable.cancelled ?? false)
    }

    func test_fileDidChangeOnDisk_deleted_setsMissingAndPreservesBuffer() throws {
        let url = try makeTempFile(content: "orig")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()

        try FileManager.default.removeItem(at: url)
        session.fileDidChangeOnDisk()

        XCTAssertEqual(session.state, .missing)
        XCTAssertEqual(session.buffer, "orig")
    }

    func test_fileDidChangeOnDisk_recreatedAfterMissing_restoresSynced() throws {
        let url = try makeTempFile(content: "orig")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        try FileManager.default.removeItem(at: url)
        session.fileDidChangeOnDisk()
        XCTAssertEqual(session.state, .missing)

        try "recreated".write(to: url, atomically: true, encoding: .utf8)
        var received: String?
        session.onExternalUpdate = { received = $0 }
        session.fileDidChangeOnDisk()

        XCTAssertEqual(session.state, .synced)
        XCTAssertEqual(session.buffer, "recreated")
        XCTAssertEqual(received, "recreated")
    }

    // MARK: - resolveConflict

    func test_resolveConflict_useDisk() throws {
        let url = try makeTempFile(content: "v1")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        session.userEdited("v1-mine")
        try "v1-external".write(to: url, atomically: true, encoding: .utf8)
        session.fileDidChangeOnDisk()
        XCTAssertEqual(session.state, .conflict)

        var received: String?
        session.onExternalUpdate = { received = $0 }
        session.resolveConflict(.useDisk)

        XCTAssertEqual(session.state, .synced)
        XCTAssertEqual(session.buffer, "v1-external")
        XCTAssertEqual(received, "v1-external")
    }

    func test_resolveConflict_keepMine() throws {
        let url = try makeTempFile(content: "v1")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        session.userEdited("v1-mine")
        try "v1-external".write(to: url, atomically: true, encoding: .utf8)
        session.fileDidChangeOnDisk()
        XCTAssertEqual(session.state, .conflict)

        session.resolveConflict(.keepMine)

        XCTAssertEqual(session.state, .synced)
        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(onDisk, "v1-mine")
    }

    // MARK: - saveAs

    func test_saveAs_writesFileAndSwitchesTarget() throws {
        let dir = try makeTempDir()
        let newURL = dir.appendingPathComponent("new.md")
        let session = DocumentSession(fileURL: nil, scheduler: FakeScheduler())
        session.userEdited("brand new content")

        try session.saveAs(newURL)

        XCTAssertEqual(session.fileURL, newURL)
        XCTAssertEqual(session.state, .synced)
        let onDisk = try String(contentsOf: newURL, encoding: .utf8)
        XCTAssertEqual(onDisk, "brand new content")
    }

    // MARK: - ensureTrailingNewline

    func test_ensureTrailingNewline_appendsOnSave() throws {
        let url = try makeTempFile(content: "line1")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        session.ensureTrailingNewline = true

        session.userEdited("line1-edited")
        scheduler.fireLatest()

        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(saved, "line1-edited\n")
    }

    func test_ensureTrailingNewline_doesNotDoubleNewline() throws {
        let url = try makeTempFile(content: "line1")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        session.ensureTrailingNewline = true

        session.userEdited("line1-edited\n")
        scheduler.fireLatest()

        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(saved, "line1-edited\n")
    }

    // MARK: - permissions

    func test_permissionsPreservedAcrossAutosave() throws {
        let url = try makeTempFile(content: "x")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()

        session.userEdited("x-edited")
        scheduler.fireLatest()

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(perms, 0o640)
    }

    // MARK: - state change notifications

    func test_onStateChange_firesOnTransitions() throws {
        let url = try makeTempFile(content: "a")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        var states: [DocumentSession.State] = []
        session.onStateChange = { states.append($0) }

        session.userEdited("a-edit")
        scheduler.fireLatest()

        XCTAssertEqual(states, [.dirty, .synced])
    }

    // MARK: - close

    func test_close_flushesPendingChangesAndStopsWatching() throws {
        let url = try makeTempFile(content: "x")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        session.userEdited("x-edited")

        session.close()

        XCTAssertEqual(session.state, .synced)
        let saved = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(saved, "x-edited")
    }

    // MARK: - real FileWatcher integration

    func test_realFileWatcher_externalAtomicOverwrite_triggersExternalUpdate() throws {
        let url = try makeTempFile(content: "start")
        let session = DocumentSession(fileURL: url)
        try session.load()

        let exp = expectation(description: "external update received")
        session.onExternalUpdate = { text in
            if text == "external-write" { exp.fulfill() }
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            try? "external-write".data(using: .utf8)!.write(to: url, options: .atomic)
        }

        wait(for: [exp], timeout: 2.0)
    }

    // MARK: - relocate（Finder などでファイルが移動・改名されたとき）

    func test_relocate_followsMovedFileWithoutRewritingIt() throws {
        let url = try makeTempFile(content: "hello")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()

        let moved = url.deletingLastPathComponent().appendingPathComponent("renamed.md")
        try FileManager.default.moveItem(at: url, to: moved)
        let modifiedBefore = try FileManager.default.attributesOfItem(atPath: moved.path)[.modificationDate] as? Date
        session.fileDidChangeOnDisk()
        XCTAssertEqual(session.state, .missing)

        session.relocate(to: moved)

        XCTAssertEqual(session.fileURL, moved)
        XCTAssertEqual(session.state, .synced)
        XCTAssertEqual(session.buffer, "hello")
        let modifiedAfter = try FileManager.default.attributesOfItem(atPath: moved.path)[.modificationDate] as? Date
        XCTAssertEqual(modifiedBefore, modifiedAfter, "relocate must not write to the file")
    }

    func test_relocate_thenAutosaveWritesToNewLocation() throws {
        let url = try makeTempFile(content: "hello")
        let scheduler = FakeScheduler()
        let session = DocumentSession(fileURL: url, scheduler: scheduler)
        try session.load()
        let moved = url.deletingLastPathComponent().appendingPathComponent("moved.md")
        try FileManager.default.moveItem(at: url, to: moved)

        session.relocate(to: moved)
        session.userEdited("hello edited")
        session.flush()

        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "hello edited")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "must not recreate the old path")
    }

    func test_relocate_picksUpContentChangedDuringTheMove() throws {
        let url = try makeTempFile(content: "hello")
        let session = DocumentSession(fileURL: url, scheduler: FakeScheduler())
        try session.load()
        var received: String?
        session.onExternalUpdate = { received = $0 }
        let moved = url.deletingLastPathComponent().appendingPathComponent("moved.md")
        try FileManager.default.moveItem(at: url, to: moved)
        try "changed elsewhere".write(to: moved, atomically: true, encoding: .utf8)

        session.relocate(to: moved)

        XCTAssertEqual(session.buffer, "changed elsewhere")
        XCTAssertEqual(received, "changed elsewhere")
        XCTAssertEqual(session.state, .synced)
    }
}
