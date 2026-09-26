import Foundation

/// One entry in the recently-opened-documents list.
public struct RecentDocument: Sendable, Equatable {
    public let url: URL
    public let opened: Date

    public init(url: URL, opened: Date) {
        self.url = url
        self.opened = opened
    }
}

/// Tracks the most recently opened documents ourselves, independent of
/// `NSDocumentController.recentDocumentURLs` (whose ~10-item cap the app can't
/// change). Backed by `UserDefaults`, mirroring the setup in `Preferences`.
public final class RecentDocuments: @unchecked Sendable {
    public static let shared = RecentDocuments()

    private let defaults: UserDefaults
    private let limit: Int

    public init(defaults: UserDefaults = .standard, limit: Int = 20) {
        self.defaults = defaults
        self.limit = limit
    }

    private enum Keys {
        static let recentDocuments = "MarkPantherCore.recentDocuments"
    }

    private struct Entry: Codable {
        let path: String
        let opened: Double
    }

    /// Pushes `url` to the front of the list. If it's already present (by
    /// canonical path) the old entry is dropped so it doesn't duplicate.
    /// Entries beyond `limit` are trimmed from the tail.
    public func record(_ url: URL) {
        let key = Self.canonicalPath(url.path)
        var entries = loadEntries().filter { Self.canonicalPath($0.path) != key }
        entries.insert(Entry(path: url.path, opened: Date().timeIntervalSince1970), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        save(entries)
    }

    /// Newest-first list of documents that still exist on disk. Entries whose
    /// file has since disappeared are dropped, and the pruned list is
    /// persisted so they stay gone on the next call.
    public func items() -> [RecentDocument] {
        let entries = loadEntries()
        let surviving = entries.filter { FileManager.default.fileExists(atPath: $0.path) }
        if surviving.count != entries.count {
            save(surviving)
        }
        return surviving.map { RecentDocument(url: URL(fileURLWithPath: $0.path), opened: Date(timeIntervalSince1970: $0.opened)) }
    }

    public func clear() {
        defaults.removeObject(forKey: Keys.recentDocuments)
    }

    // MARK: - Storage

    private func loadEntries() -> [Entry] {
        guard let data = defaults.data(forKey: Keys.recentDocuments) else { return [] }
        // Corrupt/foreign data is treated as an empty list rather than crashing.
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Keys.recentDocuments)
    }

    private static func canonicalPath(_ path: String) -> String {
        CanonicalPath.of(path)
    }
}
