import Foundation

/// One line of the Dock menu, before it becomes `NSMenuItem`s.
public enum DockMenuEntry: Sendable, Equatable {
    /// A document already open in a window; picking it brings that window forward.
    case open(title: String, path: String)
    case recent(title: String, path: String)
    case separator
    case newDocument

    public var path: String? {
        switch self {
        case .open(_, let path), .recent(_, let path): return path
        case .separator, .newDocument: return nil
        }
    }
}

/// Builds the Dock menu's contents.
///
/// Kept apart from AppKit because a Dock menu can't be driven from XCUITest —
/// this way the part that can be wrong (what appears, in what order, without
/// repeats) is covered by ordinary tests.
public enum DockMenuModel {
    public static func entries(recents: [RecentDocument], open: [URL], limit: Int = 8) -> [DockMenuEntry] {
        let openKeys = Set(open.map { CanonicalPath.of($0.path) })

        let openEntries = open.map {
            DockMenuEntry.open(title: $0.lastPathComponent, path: $0.path)
        }
        let recentEntries = recents
            .filter { !openKeys.contains(CanonicalPath.of($0.url.path)) }
            .prefix(limit)
            .map { DockMenuEntry.recent(title: $0.url.lastPathComponent, path: $0.url.path) }

        return joined([openEntries, Array(recentEntries), [.newDocument]])
    }

    /// Puts a rule between the non-empty sections only, so the menu never opens
    /// or closes on a stray line.
    private static func joined(_ sections: [[DockMenuEntry]]) -> [DockMenuEntry] {
        sections.filter { !$0.isEmpty }.enumerated().flatMap { index, section in
            index == 0 ? section : [.separator] + section
        }
    }
}
