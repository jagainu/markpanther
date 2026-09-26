import AppKit
import MarkPantherCore
import QuickLookUI
import WebKit

/// Renders a Markdown file in Finder's Quick Look with the app's own pipeline.
///
/// The rendering lives entirely in JavaScript inside the page, so matching the
/// app means running the same page here rather than reimplementing it in Swift.
/// The extension therefore carries its own copy of `preview/`.
///
/// Two things are deliberately missing compared with the app: user stylesheets
/// (a sandboxed extension can't reach the app's Application Support container)
/// and change marks (there is no previous version to diff against).
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var pageLoad: CheckedContinuation<Void, any Error>?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(stylesDirectory: Self.stylesDirectory),
                                   forURLScheme: "markp")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        try await loadPage()
        _ = try await webView.callAsyncJavaScript(
            "return await MarkPanther.render(markdown, docDir, options)",
            arguments: [
                "markdown": text,
                "docDir": url.deletingLastPathComponent().path,
                "options": Self.renderOptions(),
            ],
            in: nil,
            in: .page
        )
    }

    // MARK: - Page

    private func loadPage() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            pageLoad = continuation
            webView.load(URLRequest(url: URL(string: "markp://app/preview.html")!))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoad?.resume()
        pageLoad = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        pageLoad?.resume(throwing: error)
        pageLoad = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: any Error) {
        pageLoad?.resume(throwing: error)
        pageLoad = nil
    }

    // MARK: - Settings

    /// 拡張は自分のコンテナしか見えないので、ユーザー CSS は事実上使えない。
    /// 解決器が要求する形だけ満たしておき、読めなければ静かに失敗させる。
    private static var stylesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarkPanther/Styles", isDirectory: true)
    }

    /// 本体と同じ既定値。拡張の `UserDefaults` は本体と別ドメインなので、
    /// ここで読めるのは実質すべて初期値になる。
    private static func renderOptions() -> [String: Any] {
        let p = Preferences.shared
        return [
            "smartypants": p.smartypants, "superscript": p.superscript, "highlightMark": p.highlightMark,
            "hardLineBreaks": p.hardLineBreaks, "syntaxHighlighting": p.syntaxHighlighting,
            "codeLineNumbers": p.codeLineNumbers, "math": p.math, "frontmatter": p.frontmatter,
            "tocToken": p.tocToken, "taskList": p.taskList, "mermaid": p.mermaid,
            "lineNumbers": false,
            "changeBand": p.changeBand,
        ]
    }
}
