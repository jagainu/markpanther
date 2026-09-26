import AppKit
import UniformTypeIdentifiers

/// Copy HTML / Export HTML / Export PDF / Print。いずれもプレビューの描画結果を使う。
@MainActor
final class Exporter {
    private let preview: PreviewView

    init(preview: PreviewView) { self.preview = preview }

    func copyHTML() async {
        let html = await preview.bodyHTML()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(html, forType: .string)
    }

    func exportHTML(from window: NSWindow, suggestedName: String) async {
        let styles = NSButton(checkboxWithTitle: "Include styles", target: nil, action: nil)
        let highlight = NSButton(checkboxWithTitle: "Include syntax highlighting", target: nil, action: nil)
        styles.state = .on
        highlight.state = .on
        let accessory = NSStackView(views: [styles, highlight])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedName + ".html"
        panel.accessoryView = accessory
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        do {
            let html = try await preview.exportHTML(includeStyles: styles.state == .on,
                                                    includeHighlight: highlight.state == .on,
                                                    title: suggestedName)
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            await NSAlert(error: error).beginSheetModal(for: window)
        }
    }

    func exportPDF(from window: NSWindow, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = suggestedName + ".pdf"
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            let info = printInfo()
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            run(info, from: window, showsPanel: false)
        }
    }

    func print(from window: NSWindow) {
        run(printInfo(), from: window, showsPanel: true)
    }

    private func printInfo() -> NSPrintInfo {
        let info = NSPrintInfo(dictionary: NSPrintInfo.shared.dictionary() as? [NSPrintInfo.AttributeKey: Any] ?? [:])
        info.topMargin = 36
        info.bottomMargin = 36
        info.leftMargin = 36
        info.rightMargin = 36
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        return info
    }

    private func run(_ info: NSPrintInfo, from window: NSWindow, showsPanel: Bool) {
        let operation = preview.webView.printOperation(with: info)
        operation.showsPrintPanel = showsPanel
        operation.showsProgressPanel = showsPanel
        // WKWebView の印刷ビューは frame が空のままだと何も出力しない
        operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
