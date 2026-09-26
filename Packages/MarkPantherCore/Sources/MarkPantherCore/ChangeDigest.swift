import Foundation

/// One file's worth of external writes, merged into a single notice.
public struct DigestEntry: Sendable, Equatable {
    public let url: URL
    /// How many times the file was overwritten while the window was open.
    public let updates: Int
    /// Changed blocks, summed. `nil` when no write in this window ever reported a
    /// count — the editor doesn't render, so it can't know.
    public let changes: Int?
    public let firstSeen: Date
    public let lastSeen: Date

    public init(url: URL, updates: Int, changes: Int?, firstSeen: Date, lastSeen: Date) {
        self.url = url
        self.updates = updates
        self.changes = changes
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// Merges a burst of external overwrites into one notice per file.
///
/// Claude Code rewrites a file several times in a row, so notifying on every
/// write would bury the screen. Writes to the same file inside `window` become
/// one `DigestEntry`. The window runs from the *first* write, not the last, so
/// a tool that keeps writing can't postpone the notice forever.
///
/// Time is always passed in rather than read from the clock, so the behaviour
/// is testable and the caller can drive it from a timer it already owns.
public final class ChangeDigest: @unchecked Sendable {
    /// Changes the user hasn't looked at yet, for the Dock badge. A write with
    /// no known count still moves it by one, so the badge never stays silent.
    public private(set) var unseenTotal = 0

    private let window: TimeInterval
    private var pending: [String: DigestEntry] = [:]

    public init(window: TimeInterval = 2) {
        self.window = window
    }

    /// Records one external overwrite. `changes` is `nil` when the count isn't
    /// known yet (the window is in edit mode, so nothing re-rendered).
    public func record(url: URL, changes: Int?, at now: Date = Date()) {
        unseenTotal += changes ?? 1

        let key = CanonicalPath.of(url.path)
        guard let existing = pending[key] else {
            pending[key] = DigestEntry(url: url, updates: 1, changes: changes,
                                       firstSeen: now, lastSeen: now)
            return
        }
        pending[key] = DigestEntry(
            url: existing.url,
            updates: existing.updates + 1,
            // 件数の分かった書き込みだけを足す。全部 nil なら nil のまま
            changes: changes.map { (existing.changes ?? 0) + $0 } ?? existing.changes,
            firstSeen: existing.firstSeen,
            lastSeen: now
        )
    }

    /// Entries whose window has closed. They are handed over exactly once.
    public func due(at now: Date = Date()) -> [DigestEntry] {
        let ready = pending.filter { $0.value.firstSeen.addingTimeInterval(window) <= now }
        for key in ready.keys { pending.removeValue(forKey: key) }
        return Array(ready.values)
    }

    /// When the earliest pending entry comes due, so the caller can arm a timer.
    public var nextDue: Date? {
        pending.values.map { $0.firstSeen.addingTimeInterval(window) }.min()
    }

    /// Drops a file's pending notice — used when its window comes to the front,
    /// where the in-app indicator already says everything a banner would.
    public func forget(_ url: URL) {
        pending.removeValue(forKey: CanonicalPath.of(url.path))
    }

    public func clearUnseen() {
        unseenTotal = 0
    }
}
