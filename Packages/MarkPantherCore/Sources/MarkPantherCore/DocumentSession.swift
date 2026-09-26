import Foundation

/// Injectable debounce timer used by `DocumentSession` for autosave scheduling.
/// Production code uses `MainQueueScheduler`; tests inject a fake to control time.
public protocol SessionScheduler: Sendable {
    @MainActor func schedule(after: TimeInterval, _ work: @escaping @MainActor () -> Void) -> SessionCancellable
}

public protocol SessionCancellable {
    func cancel()
}

private final class DispatchWorkItemCancellable: SessionCancellable {
    private let workItem: DispatchWorkItem
    init(workItem: DispatchWorkItem) { self.workItem = workItem }
    func cancel() { workItem.cancel() }
}

public struct MainQueueScheduler: SessionScheduler {
    public init() {}

    @MainActor
    public func schedule(after: TimeInterval, _ work: @escaping @MainActor () -> Void) -> SessionCancellable {
        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated {
                work()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: workItem)
        return DispatchWorkItemCancellable(workItem: workItem)
    }
}

public enum DocumentSessionError: Error, Sendable {
    case encodingFailed
    case decodingFailed
}

/// Owns the in-memory buffer for a single Markdown document, keeps it synced with
/// disk via autosave + a `FileWatcher`, and arbitrates conflicts when the file
/// changes externally while the buffer has unsaved edits.
///
/// Threading: all methods must be called on the main actor. The FileWatcher used
/// internally always delivers its callback on the main queue, so `self` (though not
/// safe to share across threads in general) is only ever touched from the main actor.
@MainActor
public final class DocumentSession: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case synced
        case dirty
        case conflict
        case missing
    }

    public enum Resolution: Sendable {
        case useDisk
        case keepMine
    }

    public private(set) var buffer: String
    public private(set) var state: State {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }
    public private(set) var fileURL: URL?
    public var ensureTrailingNewline: Bool = false
    public var onExternalUpdate: ((String) -> Void)?
    public var onStateChange: ((State) -> Void)?
    public var onError: ((Error) -> Void)?

    private let autosaveDelay: TimeInterval
    private let scheduler: SessionScheduler
    /// Last buffer content known to match disk exactly. Used to distinguish a "clean"
    /// buffer (safe to overwrite with external changes) from a "dirty" one (conflict).
    private var lastSynced: String
    private var pendingSave: SessionCancellable?
    private var watcher: FileWatcher?
    private var cachedPermissions: NSNumber?

    public init(fileURL: URL?, autosaveDelay: TimeInterval = 0.5, scheduler: SessionScheduler = MainQueueScheduler()) {
        self.fileURL = fileURL
        self.autosaveDelay = autosaveDelay
        self.scheduler = scheduler
        self.buffer = ""
        self.lastSynced = ""
        self.state = .synced
    }

    deinit {
        watcher?.stop()
    }

    // MARK: - Loading

    public func load() throws {
        pendingSave?.cancel()
        pendingSave = nil

        guard let url = fileURL else {
            buffer = ""
            lastSynced = ""
            state = .synced
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .missing
            restartWatcher()
            return
        }

        let text = try readText(from: url)
        capturePermissions(at: url)
        buffer = text
        lastSynced = text
        state = .synced
        restartWatcher()
    }

    // MARK: - User edits

    public func userEdited(_ text: String) {
        buffer = text
        guard state != .conflict else { return }
        state = .dirty
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        pendingSave?.cancel()
        pendingSave = nil
        guard fileURL != nil else { return }
        pendingSave = scheduler.schedule(after: autosaveDelay) { [weak self] in
            self?.flush()
        }
    }

    // MARK: - Saving

    public func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        guard state == .dirty, let url = fileURL else { return }
        do {
            try writeAtomic(buffer, to: url)
            lastSynced = buffer
            state = .synced
        } catch {
            onError?(error)
        }
    }

    /// ファイルが Finder などで移動・改名されたあと、新しい場所を追いかける。ファイルには書き込まない。
    /// 監視先を切り替えたうえで、通常の外部変更と同じ規則（エコー抑制・clean なら取り込み・dirty なら conflict）で
    /// 現在の内容と突き合わせる。
    public func relocate(to url: URL) {
        fileURL = url
        capturePermissions(at: url)
        restartWatcher()
        fileDidChangeOnDisk()
    }

    public func saveAs(_ url: URL) throws {
        pendingSave?.cancel()
        pendingSave = nil
        try writeAtomic(buffer, to: url)
        fileURL = url
        lastSynced = buffer
        state = .synced
        capturePermissions(at: url)
        restartWatcher()
    }

    // MARK: - External changes

    public func fileDidChangeOnDisk() {
        guard let url = fileURL else { return }

        guard FileManager.default.fileExists(atPath: url.path) else {
            state = .missing
            return
        }

        let disk: String
        do {
            disk = try readText(from: url)
        } catch {
            onError?(error)
            return
        }
        capturePermissions(at: url)

        if disk == buffer {
            // Our own autosave (or an external write that happens to match). Nothing
            // to notify — just record that disk and buffer agree.
            lastSynced = disk
            if state == .missing {
                state = .synced
            }
            return
        }

        if buffer == lastSynced {
            // Buffer had no unsaved edits — safe to accept the external change.
            buffer = disk
            lastSynced = disk
            state = .synced
            onExternalUpdate?(disk)
        } else {
            // Buffer has unsaved edits that conflict with the external change.
            pendingSave?.cancel()
            pendingSave = nil
            state = .conflict
        }
    }

    public func resolveConflict(_ resolution: Resolution) {
        guard state == .conflict, let url = fileURL else { return }
        switch resolution {
        case .useDisk:
            do {
                let disk = try readText(from: url)
                capturePermissions(at: url)
                buffer = disk
                lastSynced = disk
                state = .synced
                onExternalUpdate?(disk)
            } catch {
                onError?(error)
            }
        case .keepMine:
            do {
                try writeAtomic(buffer, to: url)
                lastSynced = buffer
                state = .synced
            } catch {
                onError?(error)
            }
        }
    }

    // MARK: - Lifecycle

    public func close() {
        flush()
        watcher?.stop()
        watcher = nil
        pendingSave?.cancel()
        pendingSave = nil
    }

    // MARK: - Disk IO

    private func readText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        var convertedString: NSString?
        let usedEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: nil,
            convertedString: &convertedString,
            usedLossyConversion: nil
        )
        if usedEncoding != 0, let converted = convertedString as String? {
            return converted
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw DocumentSessionError.decodingFailed
    }

    private func writeAtomic(_ text: String, to url: URL) throws {
        var content = text
        if ensureTrailingNewline, !content.hasSuffix("\n") {
            content += "\n"
        }
        guard let data = content.data(using: .utf8) else {
            throw DocumentSessionError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        if let permissions = cachedPermissions {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }

    private func capturePermissions(at url: URL) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let permissions = attributes[.posixPermissions] as? NSNumber {
            cachedPermissions = permissions
        }
    }

    private func restartWatcher() {
        watcher?.stop()
        watcher = nil
        guard let url = fileURL else { return }
        let newWatcher = FileWatcher(url: url, queue: .main) { [weak self] in
            MainActor.assumeIsolated {
                self?.fileDidChangeOnDisk()
            }
        }
        newWatcher.start()
        watcher = newWatcher
    }
}
