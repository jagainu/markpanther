import AppKit
import MarkPantherCore

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    enum Mode: Int { case preview = 0, edit = 1 }

    let session: DocumentSession
    var onClose: (() -> Void)?

    private(set) var mode: Mode
    private let editor = EditorView(frame: NSRect(x: 0, y: 0, width: 820, height: 900))
    private let preview = PreviewView(frame: NSRect(x: 0, y: 0, width: 820, height: 900))
    private let banner = BannerView()
    private let chrome = FloatingChrome()
    private let statusBar = StatusBar()
    private let outline = OutlineSidebar(frame: NSRect(x: 0, y: 0, width: 220, height: 900))
    private let findBar = FindBar()
    private let contentContainer = NSView()
    private let overlayStack = NSStackView()  // バナーと検索バー。上段のカプセルのすぐ下に重ねる
    private let topScrim = HeaderBackdropView(frame: .zero)
    private var scrimHeight: NSLayoutConstraint!
    private var sidebarPanel: NSView!
    private var sidebarLeading: NSLayoutConstraint!
    private var contentLeading: NSLayoutConstraint!
    private var overlayTop: NSLayoutConstraint!
    private var sidebarTop: NSLayoutConstraint!
    private var layoutRectObservation: NSKeyValueObservation?
    private var isContentBuilt = false
    /// ファイルの移動・改名を追いかけるためのブックマーク（パスではなくファイルそのものを指す）
    private var fileBookmark: Data?
    private var previewIsStale = true
    /// 編集モード中に受けた外部更新。プレビューへ戻ったときに変更マークを付けるための持ち越し
    private var pendingMarkChanges = false
    /// 変更数が出そろったら通知したい、という予約（外部更新1回につき1度だけ）
    private var notifyWhenCounted = false
    /// 変更数を待っている App Intent。描画が終わるまで答えられない
    private var changeCountWaiters: [(Int) -> Void] = []
    private var wordCountWork: DispatchWorkItem?
    private var outlineWork: DispatchWorkItem?
    private var zoom: CGFloat = 1

    private static let outlineVisibleKey = "outlineVisible"
    private static let zoomKey = "viewZoom"
    private static let zoomSteps: [CGFloat] = [0.5, 0.67, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private lazy var exporter = Exporter(preview: preview)

    init(fileURL: URL?) {
        session = DocumentSession(fileURL: fileURL)
        mode = fileURL == nil ? .edit : .preview
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "MarkPantherDocument"
        window.minSize = NSSize(width: 360, height: 240)
        window.setFrameAutosaveName("MarkPantherDocument")
        if window.frame.origin == .zero { window.center() }
        // Thoughtree と同じ構成: 本文をウィンドウ全面に敷き、操作はガラスのカプセルとして上に浮かべる。
        // 中身のないコンパクトなツールバーは、信号ボタンをカプセルと同じ高さに下げるためだけに置く。
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar(identifier: "MarkPantherEmptyToolbar")
        window.toolbar?.showsBaselineSeparator = false
        window.toolbarStyle = .unifiedCompact
        buildContent()
        layoutRectObservation = window.observe(\.contentLayoutRect, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updateChromeMetrics() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// session.load() の後に呼ぶ。コールバックを結線して最初の描画を行う。
    func start() {
        session.ensureTrailingNewline = Preferences.shared.ensureTrailingNewline
        session.onExternalUpdate = { [weak self] text in self?.externalUpdate(text) }
        session.onStateChange = { [weak self] state in self?.stateChanged(state) }
        session.onError = { [weak self] error in self?.banner.show(message: "Save failed: \(error.localizedDescription)", actions: []) }
        editor.onTextChange = { [weak self] text in
            self?.session.userEdited(text)
            self?.previewIsStale = true
            self?.scheduleWordCount()
            self?.scheduleOutline()
        }
        preview.onScrollLine = { [weak self] line in
            guard let self, self.mode == .preview, !self.sidebarPanel.isHidden else { return }
            self.outline.highlightSection(containingLine: line)
        }
        editor.onScrollLine = { [weak self] line in
            guard let self, self.mode == .edit, !self.sidebarPanel.isHidden else { return }
            self.outline.highlightSection(containingLine: line)
        }
        outline.onSelect = { [weak self] item in self?.jump(toLine: item.line) }
        findBar.onSearch = { [weak self] query, backwards in self?.runFind(query, backwards: backwards) }
        findBar.onClose = { [weak self] in self?.closeFindBar() }
        preview.onLinkClicked = { [weak self] href in self?.followLink(href) }
        preview.webView.onDropFiles = { urls in
            urls.forEach { (NSApp.delegate as? AppDelegate)?.open($0) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged),
                                               name: Preferences.didChangeNotification, object: nil)

        refreshBookmark()
        editor.replaceAll(with: session.buffer)
        // load() はコールバック結線より前に状態を確定させるので、初期状態（missing など）をここで反映する
        stateChanged(session.state)
        updateTitle()
        updateStatusVisibility()
        scheduleWordCount()
        outline.update(MarkdownOutline.parse(session.buffer))
        let savedZoom = UserDefaults.standard.double(forKey: Self.zoomKey)
        applyZoom(savedZoom > 0 ? CGFloat(savedZoom) : 1, persist: false)
        show(mode, carryPosition: false)
    }

    // MARK: - Layout

    private func buildContent() {
        guard let root = window?.contentView else { return }

        for view in [preview, editor] as [NSView] {
            view.frame = contentContainer.bounds
            view.autoresizingMask = [.width, .height]
            contentContainer.addSubview(view)
        }
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentContainer)

        topScrim.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(topScrim)
        scrimHeight = topScrim.heightAnchor.constraint(equalToConstant: 56)

        // サイドバー: macOS 標準の見た目（上から下まで通しの .sidebar マテリアル。信号ボタンはこの上に乗る）
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebarPanel = sidebar
        sidebarPanel.translatesAutoresizingMaskIntoConstraints = false
        outline.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(outline)
        let sidebarEdge = NSBox()
        sidebarEdge.boxType = .separator
        sidebarEdge.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarEdge)
        root.addSubview(sidebarPanel)

        statusBar.translatesAutoresizingMaskIntoConstraints = false
        statusBar.onZoomIn = { [weak self] in self?.zoomIn(nil) }
        statusBar.onZoomOut = { [weak self] in self?.zoomOut(nil) }
        statusBar.onZoomReset = { [weak self] in self?.zoomReset(nil) }
        statusBar.onZoomChange = { [weak self] value in self?.applyZoom(value) }
        root.addSubview(statusBar)

        overlayStack.setViews([banner, findBar], in: .top)
        overlayStack.orientation = .vertical
        overlayStack.spacing = 0
        overlayStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(overlayStack)
        banner.isHidden = true
        findBar.isHidden = true

        let isOpen = UserDefaults.standard.bool(forKey: Self.outlineVisibleKey)
        sidebarLeading = sidebarPanel.leadingAnchor.constraint(
            equalTo: root.leadingAnchor, constant: isOpen ? 0 : -ChromeSpec.sidebarWidth)
        contentLeading = contentContainer.leadingAnchor.constraint(
            equalTo: root.leadingAnchor, constant: isOpen ? ChromeSpec.sidebarWidth : 0)
        sidebarTop = outline.topAnchor.constraint(equalTo: sidebarPanel.topAnchor, constant: 44)
        let sidebarStartsOpen = isOpen
        overlayTop = overlayStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 40)
        sidebarPanel.isHidden = !isOpen

        NSLayoutConstraint.activate([
            contentLeading,
            contentContainer.topAnchor.constraint(equalTo: root.topAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            scrimHeight,
            topScrim.topAnchor.constraint(equalTo: root.topAnchor),
            topScrim.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            topScrim.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            sidebarLeading, sidebarTop,
            sidebarPanel.widthAnchor.constraint(equalToConstant: ChromeSpec.sidebarWidth),
            sidebarPanel.topAnchor.constraint(equalTo: root.topAnchor),
            sidebarPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            outline.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor),
            outline.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor),
            outline.bottomAnchor.constraint(equalTo: sidebarPanel.bottomAnchor),
            sidebarEdge.topAnchor.constraint(equalTo: sidebarPanel.topAnchor),
            sidebarEdge.bottomAnchor.constraint(equalTo: sidebarPanel.bottomAnchor),
            sidebarEdge.trailingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor),
            sidebarEdge.widthAnchor.constraint(equalToConstant: 1),
            overlayTop,
            overlayStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            overlayStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            banner.widthAnchor.constraint(equalTo: overlayStack.widthAnchor),
            findBar.widthAnchor.constraint(equalTo: overlayStack.widthAnchor),
        ])

        chrome.install(in: root)
        chrome.setSidebarOpen(sidebarStartsOpen, animated: false)
        chrome.updateIndicator.onClick = { [weak self] in
            guard let self, self.mode == .preview else { return }
            self.preview.scrollToFirstChange()
        }
        chrome.updateIndicator.onDismiss = { [weak self] in self?.preview.clearChangeMarks() }
        preview.onChangesMarked = { [weak self] changed in
            guard let self else { return }
            chrome.updateIndicator.showUpdate(changes: changed)
            resumeChangeCountWaiters(changed)
            guard notifyWhenCounted else { return }
            notifyWhenCounted = false
            UpdateNotifier.shared.record(session.fileURL, changes: changed)
        }
        preview.onChangedLines = { [weak self] lines in self?.outline.markChanged(lines: lines) }
        chrome.actions.toggleSidebar = { [weak self] in self?.toggleOutline(nil) }
        chrome.actions.find = { [weak self] in self?.performFind(nil) }
        chrome.actions.selectEditing = { [weak self] isEditing in
            guard let self else { return }
            let newMode: Mode = isEditing ? .edit : .preview
            if newMode != self.mode { self.show(newMode, carryPosition: true) }
        }
        chrome.actions.format = { [weak self] index in self?.performFormat(index: index) }
        isContentBuilt = true
    }

    /// タイトルバー（タブバーが出ていればそれも含む）の高さに合わせて、カプセルの位置と本文の余白を取り直す。
    private func updateChromeMetrics() {
        // フレームの復元などで、クロームの設置前にリサイズ通知が来ることがある
        guard isContentBuilt, let window, let root = window.contentView else { return }
        let titlebarHeight = root.bounds.height - window.contentLayoutRect.maxY
        // タブバーが出ているときは、そのぶん（標準のタイトルバー 38pt を超えた分）だけヘッダを下へ伸ばす
        let tabBarHeight = max(0, titlebarHeight - 38)
        let rowCenter = ChromeSpec.headerHeight / 2
        alignTrafficLights(centerFromTop: rowCenter)
        chrome.alignTopRow(centerFromTop: rowCenter)
        chrome.layoutForWidth(root.bounds.width, isEditing: mode == .edit)

        let chromeBottom = ChromeSpec.headerHeight + tabBarHeight
        overlayTop.constant = chromeBottom
        scrimHeight.constant = chromeBottom
        sidebarTop.constant = chromeBottom
        root.layoutSubtreeIfNeeded()
        let overlayHeight = overlayStack.arrangedSubviews.filter { !$0.isHidden }.reduce(0) { $0 + $1.frame.height }
        let top = chromeBottom + overlayHeight
        preview.setInsets(top: top, bottom: 0)
        editor.setInsets(top: top, bottom: 0)
    }

    /// 信号ボタンをヘッダ帯の縦中央へ寄せる。システムはリサイズやフルスクリーン復帰のたびに標準位置へ戻すので、
    /// updateChromeMetrics から毎回呼ぶ。
    private func alignTrafficLights(centerFromTop: CGFloat) {
        guard let window else { return }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind), let holder = button.superview else { continue }
            let y = holder.bounds.height - centerFromTop - button.frame.height / 2
            if abs(button.frame.origin.y - y) > 0.5 { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y)) }
        }
    }

    // MARK: - Outline

    private func scheduleOutline() {
        guard !sidebarPanel.isHidden else { return }
        outlineWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.outline.update(MarkdownOutline.parse(self.session.buffer))
        }
        outlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func jump(toLine line: Int) {
        switch mode {
        case .preview: preview.scroll(toLine: line)
        case .edit: editor.scroll(toLine: line)
        }
    }

    @objc func toggleOutline(_ sender: Any?) {
        let willOpen = sidebarPanel.isHidden
        UserDefaults.standard.set(willOpen, forKey: Self.outlineVisibleKey)
        if willOpen {
            sidebarPanel.isHidden = false
            outline.update(MarkdownOutline.parse(session.buffer))
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = ChromeSpec.sidebarTransition
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            sidebarLeading.animator().constant = willOpen ? 0 : -ChromeSpec.sidebarWidth
            contentLeading.animator().constant = willOpen ? ChromeSpec.sidebarWidth : 0
            chrome.setSidebarOpen(willOpen, animated: true)
            window?.contentView?.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if !willOpen { self?.sidebarPanel.isHidden = true } }
        })
    }

    // MARK: - Find

    /// Edit > Find の各項目の入口。エディタでは NSTextView 標準の検索バー、プレビューでは自前の検索バーに回す。
    @objc func performFind(_ sender: Any?) {
        guard mode == .preview else {
            window?.makeFirstResponder(editor.textView)
            editor.textView.performFindPanelAction(sender)
            return
        }
        let action = (sender as? NSMenuItem).flatMap { NSTextFinder.Action(rawValue: $0.tag) } ?? .showFindInterface
        switch action {
        case .nextMatch where !findBar.isHidden:
            runFind(findBar.query, backwards: false)
        case .previousMatch where !findBar.isHidden:
            runFind(findBar.query, backwards: true)
        default:
            findBar.isHidden = false
            updateChromeMetrics()
            findBar.focus()
            if !findBar.query.isEmpty { runFind(findBar.query, backwards: false) }
        }
    }

    private func runFind(_ query: String, backwards: Bool) {
        guard !query.isEmpty else {
            preview.clearFind()
            findBar.show(current: 0, total: 0)
            return
        }
        Task {
            let result = await preview.find(query, backwards: backwards)
            findBar.show(current: result.current, total: result.total)
        }
    }

    private func closeFindBar() {
        findBar.isHidden = true
        updateChromeMetrics()
        preview.clearFind()
        if mode == .preview { window?.makeFirstResponder(preview.webView) }
    }

    // MARK: - Zoom

    private func applyZoom(_ value: CGFloat, persist: Bool = true) {
        zoom = min(max(value, Self.zoomSteps.first!), Self.zoomSteps.last!)
        preview.zoom = zoom
        editor.zoom = zoom
        statusBar.setZoom(zoom)
        if persist { UserDefaults.standard.set(Double(zoom), forKey: Self.zoomKey) }
    }

    @objc func zoomIn(_ sender: Any?) {
        applyZoom(Self.zoomSteps.first { $0 > zoom + 0.001 } ?? zoom)
    }

    @objc func zoomOut(_ sender: Any?) {
        applyZoom(Self.zoomSteps.last { $0 < zoom - 0.001 } ?? zoom)
    }

    @objc func zoomReset(_ sender: Any?) { applyZoom(1) }

    // MARK: - Mode

    private func show(_ newMode: Mode, carryPosition: Bool, then: (() -> Void)? = nil) {
        let previous = mode
        mode = newMode
        chrome.setMode(isEditing: newMode == .edit)
        if let width = window?.contentView?.bounds.width { chrome.layoutForWidth(width, isEditing: newMode == .edit) }

        switch newMode {
        case .preview:
            session.flush()
            let line = carryPosition && previous == .edit ? editor.topVisibleLine() : nil
            renderPreview { [weak self] in
                // 描画を待つ間にモードが再度切り替わっていたら、表示を奪い返さない
                guard let self, self.mode == .preview else { return }
                if let line { self.preview.scroll(toLine: line) }
                self.editor.isHidden = true
                self.preview.isHidden = false
                self.window?.makeFirstResponder(self.preview.webView)
                then?()
            }
            if previous == .preview || !carryPosition {
                editor.isHidden = true
                preview.isHidden = false
            }
        case .edit:
            if !findBar.isHidden { closeFindBar() }
            Task {
                let line = carryPosition && previous == .preview ? await preview.topLine() : nil
                guard mode == .edit else { return }
                preview.isHidden = true
                editor.isHidden = false
                if let line { editor.scroll(toLine: line) }
                window?.makeFirstResponder(editor.textView)
                then?()
            }
        }
    }

    /// Marks what changed, scrolls to the first change, and answers how many
    /// blocks changed. Driven by the Show Changes intent.
    func showChanges() async -> Int {
        window?.makeKeyAndOrderFront(nil)
        if mode != .preview { show(.preview, carryPosition: false) }
        let changed = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            changeCountWaiters.append { continuation.resume(returning: $0) }
            // 描画が件数を出さずに終わっても答えを返せるよう、完了側でも打ち切る
            renderPreview(markChanges: true) { [weak self] in self?.resumeChangeCountWaiters(0) }
        }
        preview.scrollToFirstChange()
        return changed
    }

    private func resumeChangeCountWaiters(_ changed: Int) {
        let waiters = changeCountWaiters
        changeCountWaiters = []
        waiters.forEach { $0(changed) }
    }

    /// Puts the first changed block on screen, switching to preview first if needed.
    /// Reached from the update banner and from the Show Changes intent.
    func revealFirstChange() {
        window?.makeKeyAndOrderFront(nil)
        guard mode != .preview else {
            preview.scrollToFirstChange()
            return
        }
        show(.preview, carryPosition: false) { [weak self] in self?.preview.scrollToFirstChange() }
    }

    private func renderPreview(markChanges: Bool = false, completion: (() -> Void)? = nil) {
        // 編集モード中に外から書き換えられた分も、戻ってきたときに印が出るようにする
        let mark = markChanges || pendingMarkChanges
        pendingMarkChanges = false
        previewIsStale = false
        preview.render(markdown: session.buffer,
                       docDir: session.fileURL?.deletingLastPathComponent().path,
                       markChanges: mark,
                       completion: completion)
    }

    /// エクスポート等の前に、プレビューを最新の内容へ追いつかせる。
    private func ensurePreviewCurrent() async {
        guard previewIsStale else { return }
        await withCheckedContinuation { continuation in
            renderPreview { continuation.resume() }
        }
    }


    // MARK: - Session callbacks

    private func externalUpdate(_ text: String) {
        editor.replaceAll(with: text)
        scheduleWordCount()
        scheduleOutline()
        // 反映に気づけるよう、ヘッダのファイル名の右に知らせる（変更数は描画後に上書きされる）
        chrome.updateIndicator.showUpdate(changes: nil)
        // 外部（Claude など）による上書きだけ、変わった箇所を光らせて追従する
        if mode == .preview {
            // 件数が出てから知らせる。すぐ出すと「更新されました」としか言えない
            notifyWhenCounted = true
            renderPreview(markChanges: true)
        } else {
            previewIsStale = true
            pendingMarkChanges = true
            UpdateNotifier.shared.record(session.fileURL, changes: nil)
        }
    }

    private func stateChanged(_ state: DocumentSession.State) {
        window?.isDocumentEdited = state == .dirty || state == .conflict
        switch state {
        case .conflict:
            banner.show(message: "This file was changed on disk while you were editing.", actions: [
                ("Load Disk Version", { [weak self] in self?.session.resolveConflict(.useDisk) }),
                ("Keep Mine", { [weak self] in self?.session.resolveConflict(.keepMine) }),
            ])
        case .missing:
            if followMovedFile() { return }
            banner.show(message: "The file was moved or deleted. Showing the last known content.", actions: [])
        case .synced, .dirty:
            banner.hide()
        }
        updateChromeMetrics()
    }

    @objc private func preferencesChanged() {
        session.ensureTrailingNewline = Preferences.shared.ensureTrailingNewline
        editor.applyPreferences()
        updateStatusVisibility()
        scheduleWordCount()
        if mode == .preview { renderPreview() } else { previewIsStale = true }
    }

    // MARK: - Following a moved file

    private func refreshBookmark() {
        guard let url = session.fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        fileBookmark = try? url.bookmarkData()
    }

    /// 元のパスからファイルが消えたとき、ブックマークから移動先を探して監視を引き継ぐ。
    /// ゴミ箱へ入れられた場合は追いかけない（「消えた」として扱う）。
    private func followMovedFile() -> Bool {
        guard let fileBookmark else { return false }
        var isStale = false
        guard let resolved = try? URL(resolvingBookmarkData: fileBookmark, options: [.withoutUI],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale),
              resolved.standardizedFileURL.path != session.fileURL?.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: resolved.path),
              !resolved.path.contains("/.Trash/") else { return false }
        session.relocate(to: resolved)
        refreshBookmark()
        updateTitle()
        NSDocumentController.shared.noteNewRecentDocumentURL(resolved)
        return true
    }

    // MARK: - Links

    private func followLink(_ href: String) {
        if let url = URL(string: href), let scheme = url.scheme?.lowercased(), scheme != "file" {
            if ["http", "https", "mailto"].contains(scheme) { NSWorkspace.shared.open(url) }
            return
        }
        guard let base = session.fileURL?.deletingLastPathComponent() else { return }
        let pathPart = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? href
        let decoded = pathPart.removingPercentEncoding ?? pathPart
        let target = decoded.hasPrefix("/") ? URL(fileURLWithPath: decoded)
                                           : base.appendingPathComponent(decoded).standardizedFileURL
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        if ["md", "markdown", "mdown", "mkd", "txt"].contains(target.pathExtension.lowercased()) {
            (NSApp.delegate as? AppDelegate)?.open(target)
        } else {
            NSWorkspace.shared.open(target)
        }
    }

    // MARK: - Title / status

    private func updateTitle() {
        window?.title = session.fileURL?.lastPathComponent ?? "Untitled"
        chrome.setTitle(window?.title ?? "", fileURL: session.fileURL)
        window?.representedURL = session.fileURL
        window?.subtitle = session.fileURL.map { ($0.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath } ?? ""
    }

    private func updateStatusVisibility() {
        statusBar.showsStats = Preferences.shared.showWordCount
    }

    private func scheduleWordCount() {
        guard Preferences.shared.showWordCount else { return }
        wordCountWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusBar.setStats(TextStats(self.session.buffer))
        }
        wordCountWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - Actions

    @objc func toggleMode(_ sender: Any?) {
        show(mode == .preview ? .edit : .preview, carryPosition: true)
    }

    @objc func reloadFromDisk(_ sender: Any?) {
        session.fileDidChangeOnDisk()
        preview.refreshImages()
        if mode == .preview { renderPreview() } else { previewIsStale = true }
    }

    @objc func performFormat(_ sender: Any?) {
        performFormat(index: (sender as? NSMenuItem)?.tag ?? -1)
    }

    private func performFormat(index: Int) {
        guard FormatItem.all.indices.contains(index) else { return }
        if mode == .preview { show(.edit, carryPosition: true) }
        let command = FormatItem.all[index].command
        // プレビューからの切替は非同期なので、first responder が移ってから適用する
        DispatchQueue.main.async { [weak self] in self?.editor.perform(command) }
    }

    @objc func saveDocument(_ sender: Any?) {
        if session.fileURL == nil { saveDocumentAs(sender) } else { session.flush() }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = session.fileURL?.lastPathComponent ?? "Untitled.md"
        panel.directoryURL = session.fileURL?.deletingLastPathComponent()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try self.session.saveAs(url)
                self.refreshBookmark()
                self.updateTitle()
                NSDocumentController.shared.noteNewRecentDocumentURL(url)
                RecentDocuments.shared.record(url)
            } catch {
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }

    @objc func copyHTML(_ sender: Any?) {
        Task {
            await ensurePreviewCurrent()
            await exporter.copyHTML()
        }
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let window else { return }
        Task {
            await ensurePreviewCurrent()
            await exporter.exportHTML(from: window, suggestedName: exportBaseName)
        }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let window else { return }
        Task {
            await ensurePreviewCurrent()
            exporter.exportPDF(from: window, suggestedName: exportBaseName)
        }
    }

    @objc func printDocument(_ sender: Any?) {
        guard let window else { return }
        Task {
            await ensurePreviewCurrent()
            exporter.print(from: window)
        }
    }

    private var exportBaseName: String {
        session.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMode(_:)) {
            menuItem.title = mode == .preview ? "Switch to Editor" : "Switch to Preview"
        }
        if menuItem.action == #selector(toggleOutline(_:)) {
            menuItem.title = sidebarPanel.isHidden ? "Show Outline" : "Hide Outline"
        }
        if menuItem.action == #selector(reloadFromDisk(_:)) { return session.fileURL != nil }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) { updateChromeMetrics() }

    func windowDidBecomeKey(_ notification: Notification) {
        // このファイルの知らせは、ヘッダの表示が同じことを言うので要らない
        UpdateNotifier.shared.forget(session.fileURL)
    }

    func windowDidResignKey(_ notification: Notification) {
        session.flush()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard session.fileURL == nil, !session.buffer.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save this untitled document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocumentAs(nil)
            return false
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        session.close()
        onClose?()
    }
}

/// 競合・ファイル消失を知らせる、ウィンドウ上部の細い帯。
@MainActor
final class BannerView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    private var handlers: [() -> Void] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let row = NSStackView(views: [label, NSView(), buttons])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityIdentifier("banner")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // 半透明だと下の本文が透けて読みにくいので、背景色に黄色を混ぜた不透明色にする
        var color = NSColor.textBackgroundColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.textBackgroundColor.blended(withFraction: 0.28, of: .systemYellow) ?? color
            color = color.usingColorSpace(.sRGB) ?? color
        }
        layer?.backgroundColor = color.cgColor
    }

    func show(message: String, actions: [(String, () -> Void)]) {
        label.stringValue = message
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        handlers = actions.map(\.1)
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.0, target: self, action: #selector(buttonPressed(_:)))
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = index
            buttons.addArrangedSubview(button)
        }
        isHidden = false
    }

    func hide() { isHidden = true }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }
}
