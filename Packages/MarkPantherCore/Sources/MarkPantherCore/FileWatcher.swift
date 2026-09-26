import Foundation
import CoreServices

/// Watches a single file for external changes by observing its parent directory
/// via FSEvents (per-file granularity) and filtering events down to the target file.
///
/// Rationale for watching the *parent directory* rather than the file itself:
/// external tools (including Claude Code's Write/Edit tools) frequently perform an
/// "atomic replace" — writing to a temp file and then renaming it over the target.
/// A watch on the file's own inode would miss this, since the final visible file is
/// a different inode after the rename. Watching the directory and filtering by path
/// catches every case: in-place overwrite, atomic replace, and delete+recreate.
public final class FileWatcher: @unchecked Sendable {
    private let targetPath: String
    private let parentPath: String
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var streamRef: FSEventStreamRef?

    /// - Parameters:
    ///   - url: the file to watch.
    ///   - queue: the dispatch queue `onChange` is invoked on.
    ///   - onChange: called whenever the target file changes on disk.
    public init(url: URL, queue: DispatchQueue = .main, onChange: @escaping @Sendable () -> Void) {
        self.queue = queue
        self.onChange = onChange
        self.targetPath = FileWatcher.resolvedPath(url.path)
        self.parentPath = (self.targetPath as NSString).deletingLastPathComponent
    }

    deinit {
        stopStream()
    }

    /// Resolves symlinks in `path` (e.g. /tmp -> /private/tmp) so that paths reported
    /// by FSEvents (which are already resolved) can be compared reliably.
    /// `realpath(3)` does not require the final path component to exist, so this works
    /// for files that have not been created yet.
    private static func resolvedPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return buffer.withUnsafeBufferPointer { ptr in
                String(cString: ptr.baseAddress!)
            }
        }
        return path
    }

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard streamRef == nil else { return }
        guard let stream = makeStream() else { return }
        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func makeStream() -> FSEventStreamRef? {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let pathsToWatch = [parentPath] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )
        return FSEventStreamCreate(
            kCFAllocatorDefault,
            { (_, clientCallBackInfo, numEvents, eventPaths, _, _) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvents(numEvents: numEvents, eventPaths: eventPaths)
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        )
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopStreamLocked()
    }

    private func stopStream() {
        lock.lock()
        defer { lock.unlock() }
        stopStreamLocked()
    }

    private func stopStreamLocked() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    fileprivate func handleEvents(numEvents: Int, eventPaths: UnsafeMutableRawPointer) {
        let cfArray = unsafeBitCast(eventPaths, to: CFArray.self)
        guard let paths = cfArray as? [String] else { return }
        var matched = false
        for path in paths {
            if path == targetPath || FileWatcher.resolvedPath(path) == targetPath {
                matched = true
                break
            }
        }
        if matched {
            onChange()
        }
    }
}
