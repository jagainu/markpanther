import AppIntents
import AppKit
import Foundation
import UniformTypeIdentifiers

/// "Open README in MarkPanther."
///
/// Takes either a document picked by name, or a file handed over by another
/// shortcut — the second form is what makes MarkPanther scriptable from a
/// Claude Code hook.
struct OpenMarkdownIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Markdown Document"
    static let description = IntentDescription(
        "Opens a Markdown document in MarkPanther. If it is already open, brings that window forward."
    )
    static let openAppWhenRun = true

    @Parameter(title: "Document")
    var document: MarkdownDocumentEntity?

    @Parameter(title: "File", supportedContentTypes: [.plainText])
    var file: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$document)") {
            \.$file
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = try resolvedURL() else {
            throw $document.needsValueError("Which document should MarkPanther open?")
        }
        (NSApp.delegate as? AppDelegate)?.open(url)
        return .result()
    }

    /// 明示的に渡されたファイルを優先する。名前で選ばれた document はその次。
    private func resolvedURL() throws -> URL? {
        if let fileURL = file?.fileURL { return fileURL }
        return document?.url
    }
}
