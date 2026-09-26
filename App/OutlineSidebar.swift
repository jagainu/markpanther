import AppKit
import MarkPantherCore

/// 見出しのアウトライン。行を選ぶとその見出しへ飛ぶ。表示中の節は選択状態で示す。
@MainActor
final class OutlineSidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((OutlineItem) -> Void)?

    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "No headings")
    private var items: [OutlineItem] = []
    /// 変更のあった節（items の添字）。行ではなく節で持つのは、セルがそれだけ知れば描けるため
    private var changedSections: Set<Int> = []
    private var currentLine = 0
    private var isSelectingProgrammatically = false

    override init(frame: NSRect) {
        super.init(frame: frame)

        let column = NSTableColumn(identifier: .init("title"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        // `.sourceList` は選択を vibrant な選択マテリアルで描くため、行側の drawSelection が
        // 効かず灰色の丸みになる。選択は自前で塗るので `.plain` にする（[AccentRowView]）。
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.rowSizeStyle = .small
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.setAccessibilityIdentifier("outline")

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyLabel.alignment = .center

        for view in [scroll, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ newItems: [OutlineItem]) {
        guard newItems != items else { return }
        items = newItems
        emptyLabel.isHidden = !items.isEmpty
        tableView.reloadData()
        highlightSection(containingLine: currentLine)
    }

    /// 変更のあったソース行（0 始まり）を、それを含む節に畳んで印を付ける。
    /// 見出しより前の本文で変わった箇所は、どの節にも属さないので落ちる。
    func markChanged(lines: [Int]) {
        var sections: Set<Int> = []
        for line in lines {
            guard let index = items.lastIndex(where: { $0.line <= line }) else { continue }
            sections.insert(index)
        }
        guard sections != changedSections else { return }
        changedSections = sections
        tableView.reloadData()
    }

    /// 表示中の位置（画面上端のソース行）を含む節を選択状態にする。onSelect は呼ばない。
    func highlightSection(containingLine line: Int) {
        currentLine = line
        let row = items.lastIndex { $0.line <= line }
        guard tableView.selectedRow != (row ?? -1) else { return }
        isSelectingProgrammatically = true
        defer { isSelectingProgrammatically = false }
        if let row {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        AccentRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? OutlineCell ?? OutlineCell(identifier)
        let base = items.map(\.level).min() ?? 1
        cell.configure(items[row], indentLevel: items[row].level - base,
                       changed: changedSections.contains(row))
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // キーボードで選択を動かしたときも追従する（クリックは rowClicked 側で処理）
        guard !isSelectingProgrammatically, window?.firstResponder === tableView,
              NSApp.currentEvent?.type == .keyDown else { return }
        selectCurrentRow()
    }

    @objc private func rowClicked() { selectCurrentRow() }

    private func selectCurrentRow() {
        let row = tableView.selectedRow
        guard items.indices.contains(row) else { return }
        onSelect?(items[row])
    }
}

private final class OutlineCell: NSTableCellView {
    private let label = NSTextField(labelWithString: "")
    /// その節に変更があることを示す丸。本文の左余白に出るものと同じ意味・同じ色
    private let dot = NSView()
    private var leading: NSLayoutConstraint!

    init(_ identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = AppAccent.Update.accent(dark: false).cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        NSLayoutConstraint.activate([
            leading,
            label.trailingAnchor.constraint(equalTo: dot.leadingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 行と同じ理由で vibrancy を切る（[AccentRowView] 参照）。
    /// 効かせたままだと、塗りの上の白文字が背景と混ざって読みにくくなる。
    override var allowsVibrancy: Bool { false }

    /// 選択された行はアクセント色で塗られるので、文字は白に切り替える。
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyTextColor() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyDotColor()
    }

    private func applyDotColor() {
        // 選択行はアクセントで塗られていて、その上のピンクの丸は沈む。文字と同じく白に抜く
        if backgroundStyle == .emphasized {
            dot.layer?.backgroundColor = AppAccent.onSelection.cgColor
            return
        }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        dot.layer?.backgroundColor = AppAccent.Update.accent(dark: isDark).cgColor
    }

    private var restingColor: NSColor = .labelColor

    private func applyTextColor() {
        label.textColor = backgroundStyle == .emphasized ? AppAccent.onSelection : restingColor
        applyDotColor()
    }

    func configure(_ item: OutlineItem, indentLevel: Int, changed: Bool) {
        label.stringValue = item.title
        label.toolTip = item.title
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: item.level == 1 ? .semibold : .regular)
        restingColor = item.level <= 2 ? .labelColor : .secondaryLabelColor
        applyTextColor()
        dot.isHidden = !changed
        applyDotColor()
        leading.constant = 4 + CGFloat(indentLevel) * 12
    }
}
