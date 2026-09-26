import AppIntents
import Foundation
import MarkPantherCore

/// A Markdown file, as Siri and Shortcuts see it.
///
/// Identified by canonical path so the same file picked from the recents list
/// and from the project index is one entity.
struct MarkdownDocumentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Markdown Document"
    static let defaultQuery = MarkdownDocumentQuery()

    let id: String
    let name: String
    let folder: String

    var url: URL { URL(fileURLWithPath: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(folder)")
    }

    init(url: URL) {
        id = CanonicalPath.of(url.path)
        name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        folder = parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}

/// Resolves a spoken or typed name to a document.
///
/// Looks at what the user has opened recently first, then the enclosing
/// project — see [DocumentLookup].
struct MarkdownDocumentQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MarkdownDocumentEntity] {
        identifiers
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { MarkdownDocumentEntity(url: URL(fileURLWithPath: $0)) }
    }

    func entities(matching string: String) async throws -> [MarkdownDocumentEntity] {
        Self.search(string)
    }

    func suggestedEntities() async throws -> [MarkdownDocumentEntity] {
        Self.search("")
    }

    private static func search(_ query: String) -> [MarkdownDocumentEntity] {
        let recents = RecentDocuments.shared.items()
        // プロジェクトは「いちばん最近開いたファイル」の属する木を見る。
        // 何も開いたことがなければ最近のものだけで引く
        let project = recents.first.map { ProjectIndex.scan(root: ProjectRoot.find(for: $0.url)) } ?? []
        return DocumentLookup.find(query: query, recents: recents, project: project)
            .map { MarkdownDocumentEntity(url: $0.url) }
    }
}
