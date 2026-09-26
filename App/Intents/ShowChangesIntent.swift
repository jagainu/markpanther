import AppIntents
import AppKit
import Foundation
import UniformTypeIdentifiers

/// Opens a document, marks what changed, and scrolls to the first change.
///
/// The point of this one is automation: a Claude Code hook can run it the
/// moment the agent finishes writing, and the diff is on screen without the
/// user going to look for it. It returns the number of changed blocks so a
/// shortcut can branch on "did anything actually change".
struct ShowChangesIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Changes"
    static let description = IntentDescription(
        "Opens a Markdown document in MarkPanther, marks what changed since it was last read, and scrolls to the first change."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Document")
    var document: MarkdownDocumentEntity?

    @Parameter(title: "File", supportedContentTypes: [.plainText])
    var file: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Show changes in \(\.$document)") {
            \.$file
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        guard let url = file?.fileURL ?? document?.url else {
            throw $document.needsValueError("Which document should MarkPanther show changes for?")
        }
        guard let delegate = NSApp.delegate as? AppDelegate else { return .result(value: 0) }
        return .result(value: await delegate.showChanges(url))
    }
}
