import AppKit
import MarkPantherCore

/// ⌘O の Quick Open パネル。直近ドキュメントを絞り込んで開く。
/// メニューへの結線はしない — 呼び出し側が `QuickOpenPanel.shared.present { url in ... }` を呼ぶ。
@MainActor
final class QuickOpenPanel: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = QuickOpenPanel()

    private enum Spec {
        static let width: CGFloat = 620
        static let cornerRadius: CGFloat = 14
        static let fieldHeight: CGFloat = 52
        static let rowHeight: CGFloat = 44
        static let emptyHeight: CGFloat = 80
        static let maxVisibleRows = 8
        /// パネル上端を画面上部からどれくらいの割合下げるか（Spotlight 的に中央よりやや上）。
        static let topInsetRatio: CGFloat = 0.22
    }

    private let field = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No matching documents")

    private var allItems: [RecentDocument] = []
    private var filtered: [RecentDocument] = []
    private var onOpen: ((URL) -> Void)?
    /// present() のたびに決め直す、パネルの上端 y 座標。フィルタで行数が変わっても
    /// 入力欄の位置は動かさず、下に伸び縮みさせるための基準点。
    private var topY: CGFloat = 0

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Spec.width, height: Spec.fieldHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        super.init(window: panel)
        panel.delegate = self
        buildContent(in: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    private func buildContent(in panel: NSPanel) {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Spec.cornerRadius
        background.layer?.masksToBounds = true
        panel.contentView = background

        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.placeholderString = "Open Recent Document"
        field.delegate = self
        field.setAccessibilityIdentifier("quickOpenField")

        let separator = NSBox()
        separator.boxType = .separator

        let column = NSTableColumn(identifier: .init("quickOpenColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.rowSizeStyle = .medium
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowClicked)
        tableView.setAccessibilityIdentifier("quickOpenList")

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        emptyLabel.alignment = .center

        for view in [field, separator, scrollView, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: background.topAnchor),
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -18),
            field.heightAnchor.constraint(equalToConstant: Spec.fieldHeight),

            separator.topAnchor.constraint(equalTo: field.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: background.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 28),
        ])
    }

    // MARK: - Presentation

    /// パネルを画面中央上寄りに出す。選ばれたら onOpen を呼んで閉じる。
    func present(onOpen: @escaping (URL) -> Void) {
        self.onOpen = onOpen
        allItems = RecentDocuments.shared.items()
        field.stringValue = ""
        applyFilter(resetPosition: true)

        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    private func dismiss() {
        window?.orderOut(nil)
        onOpen = nil
    }

    // MARK: - Filtering

    private func applyFilter(resetPosition: Bool = false) {
        let query = field.stringValue
        filtered = FuzzyMatch.rank(query: query, items: allItems)
        tableView.reloadData()
        emptyLabel.isHidden = !filtered.isEmpty
        scrollView.isHidden = filtered.isEmpty

        resize(resetPosition: resetPosition)

        if !filtered.isEmpty {
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    private func currentHeight() -> CGFloat {
        if filtered.isEmpty {
            return Spec.fieldHeight + Spec.emptyHeight
        }
        let rows = min(filtered.count, Spec.maxVisibleRows)
        return Spec.fieldHeight + CGFloat(rows) * Spec.rowHeight
    }

    private func resize(resetPosition: Bool) {
        guard let window else { return }
        let height = currentHeight()
        let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let x: CGFloat
        if resetPosition {
            x = screenFrame.midX - Spec.width / 2
            topY = screenFrame.maxY - screenFrame.height * Spec.topInsetRatio
        } else {
            x = window.frame.origin.x
        }

        window.setFrame(NSRect(x: x, y: topY - height, width: Spec.width, height: height), display: true)
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = tableView.selectedRow
        let base = current < 0 ? 0 : current
        let next = min(max(base + delta, 0), filtered.count - 1)
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func rowClicked() { openSelected() }

    private func openSelected() {
        guard filtered.indices.contains(tableView.selectedRow) else { return }
        let url = filtered[tableView.selectedRow].url
        let callback = onOpen
        dismiss()
        callback?(url)
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { Spec.rowHeight }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        AccentRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("quickOpenCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? QuickOpenCell ?? QuickOpenCell(identifier)
        cell.configure(url: filtered[row].url, query: field.stringValue)
        return cell
    }
}

/// 2段組みの行: ファイル名（本文色）＋ 親ディレクトリのパス（`~` 短縮、副次色）。
/// クエリにマッチした文字は太字にする。
private final class QuickOpenCell: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    init(_ identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        nameLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pathLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [nameLabel, pathLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = nameLabel
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(url: URL, query: String) {
        let name = url.lastPathComponent
        let directory = Self.shortenedHome(url.deletingLastPathComponent().path)

        let nameFont = NSFont.systemFont(ofSize: 14)
        let nameBoldFont = NSFont.boldSystemFont(ofSize: 14)
        let pathFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let pathBoldFont = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        // ファイル名内で当たればそちらを太字にする。当たらなければパス側を試す
        // （ランキング自体は FuzzyMatch.rank がフルパスで既に済ませている。ここは表示上の強調だけ）。
        if !query.isEmpty, let match = FuzzyMatch.match(query: query, candidate: name) {
            nameLabel.attributedStringValue = Self.attributed(name, boldAt: match.matchedIndexes, font: nameFont, boldFont: nameBoldFont, color: .labelColor)
            pathLabel.stringValue = directory
            pathLabel.font = pathFont
        } else if !query.isEmpty, let match = FuzzyMatch.match(query: query, candidate: directory) {
            nameLabel.stringValue = name
            nameLabel.font = nameFont
            nameLabel.textColor = .labelColor
            pathLabel.attributedStringValue = Self.attributed(directory, boldAt: match.matchedIndexes, font: pathFont, boldFont: pathBoldFont, color: .secondaryLabelColor)
        } else {
            nameLabel.stringValue = name
            nameLabel.font = nameFont
            nameLabel.textColor = .labelColor
            pathLabel.stringValue = directory
            pathLabel.font = pathFont
        }
        nameLabel.toolTip = url.path
    }

    private static func shortenedHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }

    private static func attributed(_ text: String, boldAt indexes: [Int], font: NSFont, boldFont: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let boldIndexes = Set(indexes)
        let characters = Array(text)
        for i in characters.indices where boldIndexes.contains(i) {
            result.addAttribute(.font, value: boldFont, range: NSRange(location: i, length: 1))
        }
        return result
    }
}
