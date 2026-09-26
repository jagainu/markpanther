import AppKit
import MarkPantherCore
import WebKit

/// ファイルのドロップをページ遷移ではなく「アプリで開く」に回す WKWebView。
final class DropForwardingWebView: WKWebView {
    var onDropFiles: (([URL]) -> Void)?

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    private func fileURLs(_ sender: any NSDraggingInfo) -> [URL] {
        let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                            options: [.urlReadingFileURLsOnly: true])
        return (objects as? [URL]) ?? []
    }
}

@MainActor
final class PreviewView: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    private static let pageURL = URL(string: "markp://app/preview.html")!

    /// リンクのクリックを拾って生の href を Swift に渡す。ページ内アンカーだけは JS 側でスクロールする。
    private static let linkScript = """
    document.addEventListener('click', function (event) {
      var a = event.target.closest ? event.target.closest('a[href]') : null;
      if (!a) return;
      var href = a.getAttribute('href');
      event.preventDefault();
      if (href.charAt(0) === '#') {
        var id = decodeURIComponent(href.slice(1));
        var target = document.getElementById(id) || document.getElementsByName(id)[0];
        if (target) target.scrollIntoView();
        return;
      }
      window.webkit.messageHandlers.markpantherLink.postMessage(href);
    }, true);
    """

    /// スクロール位置（画面上端のソース行）を間引いて Swift に通知する。アウトラインの現在位置表示用。
    private static let scrollScript = """
    (function () {
      var timer = null;
      window.addEventListener('scroll', function () {
        if (timer) return;
        timer = setTimeout(function () {
          timer = null;
          if (window.MarkPanther) window.webkit.messageHandlers.markpantherScroll.postMessage(MarkPanther.getTopLine());
        }, 120);
      }, { passive: true });
    })();
    """

    let webView: DropForwardingWebView
    var onLinkClicked: ((String) -> Void)?
    var onScrollLine: ((Int) -> Void)?
    /// markChanges 付きの描画が終わったとき。引数は変わったブロックの数
    var onChangesMarked: ((Int) -> Void)?
    /// 印の付いた場所のソース行（0 始まり）。描画のたびに渡る。サイドバー用
    var onChangedLines: (([Int]) -> Void)?

    private var isLoaded = false
    private var pending: (markdown: String, docDir: String?, markChanges: Bool, completion: [() -> Void])?
    private var lastJob: (markdown: String, docDir: String?)?
    private var appliedStyle: String?
    private var insets: (top: CGFloat, bottom: CGFloat) = (0, 0)

    override init(frame: NSRect) {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(AssetSchemeHandler(stylesDirectory: AppDelegate.stylesDirectory),
                                   forURLScheme: "markp")
        config.userContentController.addUserScript(
            WKUserScript(source: Self.linkScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.addUserScript(
            WKUserScript(source: Self.scrollScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = DropForwardingWebView(frame: frame, configuration: config)
        super.init(frame: frame)

        config.userContentController.add(WeakMessageHandler(self), name: "markpantherLink")
        config.userContentController.add(WeakMessageHandler(self), name: "markpantherScroll")
        config.userContentController.add(WeakMessageHandler(self), name: "markpantherCopy")
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("preview")
        addSubview(webView)
        webView.load(URLRequest(url: Self.pageURL))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Rendering

    /// markChanges: 外部からの上書きを反映するときだけ true。変わったブロックを一瞬光らせ、画面外ならそこへスクロールする。
    func render(markdown: String, docDir: String?, markChanges: Bool = false, completion: (() -> Void)? = nil) {
        var completions = pending?.completion ?? []
        if let completion { completions.append(completion) }
        pending = (markdown, docDir, markChanges || (pending?.markChanges ?? false), completions)
        flushPending()
    }

    private func flushPending() {
        guard isLoaded, let job = pending else { return }
        pending = nil
        lastJob = (job.markdown, job.docDir)
        applyStyleIfNeeded()
        var options = Self.renderOptions()
        options["markChanges"] = job.markChanges
        let arguments: [String: Any] = [
            "markdown": job.markdown,
            "docDir": job.docDir ?? NSNull(),
            "options": options,
        ]
        webView.callAsyncJavaScript("return await MarkPanther.render(markdown, docDir, options)",
                                    arguments: arguments, in: nil, in: .page) { [weak self] result in
            switch result {
            case .failure(let error):
                NSLog("MarkPanther render failed: \(error)")
            case .success(let value):
                let payload = value as? [String: Any]
                let changed = (payload?["changed"] as? NSNumber)?.intValue ?? 0
                if job.markChanges { self?.onChangesMarked?(changed) }
                let lines = (payload?["changedLines"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
                self?.onChangedLines?(lines)
            }
            job.completion.forEach { $0() }
        }
    }

    /// 変更の印だけを取り払う（本文はそのまま）。
    func clearChangeMarks() {
        onChangedLines?([])
        guard isLoaded else { return }
        webView.callAsyncJavaScript("MarkPanther.clearChangeMarks()", arguments: [:], in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("MarkPanther clearChangeMarks failed: \(error)") }
        }
    }

    private func applyStyleIfNeeded() {
        let style = Preferences.shared.styleName
        guard style != appliedStyle else { return }
        appliedStyle = style
        webView.callAsyncJavaScript("MarkPanther.setStyle(name)", arguments: ["name": style],
                                    in: nil, in: .page, completionHandler: nil)
    }

    private static func renderOptions() -> [String: Any] {
        let p = Preferences.shared
        return [
            "smartypants": p.smartypants, "superscript": p.superscript, "highlightMark": p.highlightMark,
            "hardLineBreaks": p.hardLineBreaks, "syntaxHighlighting": p.syntaxHighlighting,
            "codeLineNumbers": p.codeLineNumbers, "math": p.math, "frontmatter": p.frontmatter,
            "tocToken": p.tocToken, "taskList": p.taskList, "mermaid": p.mermaid,
            "lineNumbers": p.previewLineNumbers,
            "changeBand": p.changeBand,
        ]
    }

    // MARK: - JS API

    func topLine() async -> Int {
        let value = try? await webView.callAsyncJavaScript("return MarkPanther.getTopLine()", contentWorld: .page)
        return (value as? NSNumber)?.intValue ?? 0
    }

    func scroll(toLine line: Int) {
        webView.callAsyncJavaScript("MarkPanther.scrollToLine(line)", arguments: ["line": line],
                                    in: nil, in: .page, completionHandler: nil)
    }

    /// 同じ query で呼ぶたびに次（backwards なら前）の一致へ進む。戻り値は (現在位置 1 始まり, 総数)。
    func find(_ query: String, backwards: Bool) async -> (current: Int, total: Int) {
        let value = try? await webView.callAsyncJavaScript(
            "return MarkPanther.find(query, {backwards: backwards})",
            arguments: ["query": query, "backwards": backwards], contentWorld: .page)
        let result = value as? [String: Any]
        return ((result?["current"] as? NSNumber)?.intValue ?? 0, (result?["total"] as? NSNumber)?.intValue ?? 0)
    }

    /// 次の render でローカル画像を取り直させる（あとから作られた・差し替えられた画像用）。
    func refreshImages() {
        webView.callAsyncJavaScript("MarkPanther.bumpImageVersion()", arguments: [:], in: nil, in: .page, completionHandler: nil)
    }

    /// 上下に浮いているクロームのぶんの余白。ページの読み込み前に呼ばれても、読み込み後に反映する。
    func setInsets(top: CGFloat, bottom: CGFloat) {
        guard insets.top != top || insets.bottom != bottom else { return }
        insets = (top, bottom)
        applyInsets()
    }

    private func applyInsets() {
        guard isLoaded else { return }
        webView.callAsyncJavaScript("MarkPanther.setInsets(top, bottom)",
                                    arguments: ["top": Double(insets.top), "bottom": Double(insets.bottom)],
                                    in: nil, in: .page, completionHandler: nil)
    }

    func scrollToFirstChange() {
        webView.callAsyncJavaScript("MarkPanther.scrollToFirstChange()", arguments: [:], in: nil, in: .page,
                                    completionHandler: nil)
    }

    func clearFind() {
        webView.callAsyncJavaScript("MarkPanther.clearFind()", arguments: [:], in: nil, in: .page, completionHandler: nil)
    }

    /// 表示倍率。ページズームではなく CSS 側で拡大する（理由は preview.js の setZoom を参照）。
    var zoom: CGFloat = 1 {
        didSet { if zoom != oldValue { applyZoom() } }
    }

    private func applyZoom() {
        guard isLoaded else { return }
        webView.callAsyncJavaScript("MarkPanther.setZoom(zoom)", arguments: ["zoom": Double(zoom)],
                                    in: nil, in: .page, completionHandler: nil)
    }

    func bodyHTML() async -> String {
        let value = try? await webView.callAsyncJavaScript("return MarkPanther.getBodyHTML()", contentWorld: .page)
        return value as? String ?? ""
    }

    func exportHTML(includeStyles: Bool, includeHighlight: Bool, title: String) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            "return await MarkPanther.exportHTML({includeStyles: styles, includeHighlight: highlight, title: title})",
            arguments: ["styles": includeStyles, "highlight": includeHighlight, "title": title],
            contentWorld: .page)
        return value as? String ?? ""
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        applyInsets()
        applyZoom()
        // Web プロセスが落ちて再読み込みした場合は、最後の内容を描き直す
        if pending == nil, let lastJob { pending = (lastJob.markdown, lastJob.docDir, false, []) }
        flushPending()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction)
        async -> WKNavigationActionPolicy {
        // 許可するのは最初のページ読み込みだけ。リンクは linkScript 経由で処理する。
        var target = navigationAction.request.url
        if var components = target.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
            components.fragment = nil
            target = components.url
        }
        return target == Self.pageURL ? .allow : .cancel
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoaded = false
        appliedStyle = nil
        webView.load(URLRequest(url: Self.pageURL))
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "markpantherLink", let href = message.body as? String { onLinkClicked?(href) }
        if message.name == "markpantherScroll", let line = message.body as? NSNumber { onScrollLine?(line.intValue) }
        if message.name == "markpantherCopy", let text = message.body as? String {
            // コードブロックの Copy ボタン。ページ側にクリップボード権限は与えず、ここで書き込む。
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}

/// WKUserContentController は handler を強参照するので循環を避ける。
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?
    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
