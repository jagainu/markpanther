import Foundation

/// Finds a document by name across what the user has opened and what the
/// project holds.
///
/// Used by the App Intents entity query, so Siri and Shortcuts can take a bare
/// name ("README") and land on a file. Kept in Core, and free of AppKit, so the
/// ranking can be tested without a running app.
public enum DocumentLookup {
    /// Everything worth offering, newest-first, with each file appearing once.
    /// Recently opened files win over mere project files: having opened it is
    /// the stronger signal of what the user means.
    public static func candidates(recents: [RecentDocument], project: [ProjectFile]) -> [RecentDocument] {
        var seen = Set<String>()
        var result: [RecentDocument] = []

        for document in recents + project.map({ RecentDocument(url: $0.url, opened: $0.modified) }) {
            let key = CanonicalPath.of(document.url.path)
            guard seen.insert(key).inserted else { continue }
            result.append(document)
        }
        return result
    }

    public static func find(query: String, recents: [RecentDocument], project: [ProjectFile],
                            limit: Int = 12) -> [RecentDocument] {
        let ranked = FuzzyMatch.rank(query: query, items: candidates(recents: recents, project: project))
        return Array(ranked.prefix(limit))
    }
}
