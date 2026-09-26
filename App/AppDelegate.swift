import AppKit
import MarkPantherCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controllers: [DocumentWindowController] = []
    private var preferencesWindow: PreferencesWindowController?
    private let recentMenu = NSMenu(title: "Open Recent")
    private var didOpenFileAtLaunch = false

    // MARK: - Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(recentMenu: recentMenu)
        recentMenu.delegate = self
        try? FileManager.default.createDirectory(at: Self.stylesDirectory, withIntermediateDirectories: true)
        UpdateNotifier.shared.onOpen = { [weak self] url in self?.reveal(url) }
        UpdateNotifier.shared.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI テストや CLI から `--open <path>` でも開けるようにする
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--open"), i + 1 < args.count {
            open(URL(fileURLWithPath: args[i + 1]))
            if args.contains("--edit") { controllers.last?.toggleMode(nil) }
            if args.contains("--find") {  // 見た目の検証用: 検索バーを開いた状態で起動する
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.controllers.last?.performFind(nil)
                }
            }
        }
        if controllers.isEmpty, !didOpenFileAtLaunch, Preferences.shared.openUntitledOnLaunch {
            newDocument(nil)
        }
        // 前面に出すかどうかは起動元（open / open -g）に任せる。ここで activate するとフック経由の
        // バックグラウンド起動でもフォーカスを奪ってしまう。
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didOpenFileAtLaunch = true
        urls.forEach(open)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDocument(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        UpdateNotifier.shared.markSeen()
        // システム設定で後から許可されても、再起動せずに効くように取り直す
        Task { await UpdateNotifier.shared.refreshAuthorization() }
    }

    /// Dock アイコンの右クリック。開いているものと最近のものを出す。
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let entries = DockMenuModel.entries(recents: RecentDocuments.shared.items(),
                                            open: controllers.compactMap { $0.session.fileURL })
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .newDocument:
                let item = NSMenuItem(title: "New Document", action: #selector(newDocument(_:)), keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            case .open(let title, let path), .recent(let title, let path):
                let item = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.representedObject = URL(fileURLWithPath: path)
                item.toolTip = path
                item.target = self
                menu.addItem(item)
            }
        }
        return menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.session.close() }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    static var stylesDirectory: URL {
        supportDirectory.appendingPathComponent("Styles", isDirectory: true)
    }

    private static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarkPanther", isDirectory: true)
    }

    // MARK: - Opening

    func open(_ url: URL) {
        let key = Self.canonical(url)
        if let existing = controllers.first(where: { $0.session.fileURL.map(Self.canonical) == key }) {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = DocumentWindowController(fileURL: url)
        do {
            try controller.session.load()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        present(controller)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        RecentDocuments.shared.record(url)
    }

    /// Opens `url` and puts the first changed block on screen. Used by the update
    /// banner and by the Show Changes intent.
    func reveal(_ url: URL) {
        open(url)
        let key = Self.canonical(url)
        controllers.first { $0.session.fileURL.map(Self.canonical) == key }?.revealFirstChange()
    }

    /// Opens `url`, marks what changed and returns how many blocks changed.
    /// Used by the Show Changes intent.
    func showChanges(_ url: URL) async -> Int {
        open(url)
        let key = Self.canonical(url)
        guard let controller = controllers.first(where: { $0.session.fileURL.map(Self.canonical) == key })
        else { return 0 }
        return await controller.showChanges()
    }

    private func present(_ controller: DocumentWindowController) {
        controllers.append(controller)
        controller.onClose = { [weak self, weak controller] in
            self?.controllers.removeAll { $0 === controller }
        }
        controller.start()
        if let front = NSApp.mainWindow, front.windowController is DocumentWindowController,
           let window = controller.window {
            window.setFrameTopLeftPoint(front.cascadeTopLeft(from: NSPoint(x: front.frame.minX, y: front.frame.maxY)))
        }
        controller.showWindow(nil)
    }

    private static func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Actions

    @objc func newDocument(_ sender: Any?) {
        present(DocumentWindowController(fileURL: nil))
    }

    /// 直近に開いた md から絞り込んで開く（⌘O）。
    @objc func quickOpen(_ sender: Any?) {
        QuickOpenPanel.shared.present { [weak self] url in self?.open(url) }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK { panel.urls.forEach(open) }
    }

    /// Claude Code が plan mode で書き出したプランのうち、最後に更新されたものを開く。
    @objc func openLatestPlan(_ sender: Any?) {
        let directory = Self.claudePlansDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let latest = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .max { Self.modificationDate($0) < Self.modificationDate($1) }
        guard let latest else {
            let alert = NSAlert()
            alert.messageText = "No Claude Code plans found"
            alert.informativeText = "Looked in \((directory.path as NSString).abbreviatingWithTildeInPath)."
            alert.runModal()
            return
        }
        open(latest)
    }

    /// 既定は ~/.claude/plans。~/.claude/settings.json の plansDirectory で変更されていればそちら。
    private static var claudePlansDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settings = home.appendingPathComponent(".claude/settings.json")
        if let data = try? Data(contentsOf: settings),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let custom = json["plansDirectory"] as? String, !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, relativeTo: home)
        }
        return home.appendingPathComponent(".claude/plans", isDirectory: true)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWindow == nil { preferencesWindow = PreferencesWindowController() }
        preferencesWindow?.showWindow(nil)
        preferencesWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { open(url) }
    }

    @objc func clearRecent(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    /// Copies the `markp` shell command out of the bundle into `~/.local/bin`.
    ///
    /// `make install` puts it there straight from the repository, but a copy of
    /// the app handed to another Mac has no repository to copy from — so the
    /// command ships inside the bundle and gets installed from here.
    @objc func installCommandLineTool(_ sender: Any?) {
        let alert = NSAlert()
        guard let source = Bundle.main.url(forResource: "markp", withExtension: nil) else {
            alert.alertStyle = .warning
            alert.messageText = "This copy of MarkPanther doesn't include the command line tool."
            alert.runModal()
            return
        }

        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        let destination = directory.appendingPathComponent("markp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 入れ直しも想定するので、既にあるものは置き換える
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        } catch {
            alert.alertStyle = .warning
            alert.messageText = "Couldn't install the command line tool."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return
        }

        alert.messageText = "\u{2018}markp\u{2019} installed."
        // PATH は GUI から見えるものがシェルのそれと違うので、こちらで判定せず案内だけする
        alert.informativeText = """
            Installed at \(destination.path).

            If your shell can't find it, add this to your profile:
            export PATH="$HOME/.local/bin:$PATH"
            """
        alert.runModal()
    }

    // MARK: - Open Recent

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url
            item.toolTip = url.path
            item.target = self
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }
}
