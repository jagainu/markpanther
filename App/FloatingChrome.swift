import AppKit
import MarkPantherCore

/// フローティングクロームの寸法。Thoughtree（Freeform 準拠）の構成を、文書ビューア向けに低めにしたもの。
enum ChromeSpec {
    static let capsuleHeight: CGFloat = 26
    static let buttonSize: CGFloat = 24
    static let iconPointSize: CGFloat = 13
    static let itemSpacing: CGFloat = 2
    /// ヘッダ帯の高さ。標準のコンパクトなタイトルバー（38pt）よりひと回り高くし、信号ボタンもこの中央へ寄せる
    static let headerHeight: CGFloat = 46
    static let windowInset: CGFloat = 8
    static let groupSpacing: CGFloat = 8
    static let trafficLightClearance: CGFloat = 84
    static let sidebarWidth: CGFloat = 230
    static let sidebarTransition: TimeInterval = 0.22
}

/// Liquid Glass の共通ラッパー。macOS 26 以降は NSGlassEffectView、それ未満は NSVisualEffectView。
/// Thoughtree の GlassEffectWrapperView と同じ分岐を 1 箇所に集約する。
@MainActor
enum Glass {
    /// panel を階層に追加し、中身は host に入れる。
    static func make(cornerRadius: CGFloat) -> (panel: NSView, host: NSView) {
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            let content = NSView()
            glass.contentView = content
            return (glass, content)
        }
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        return (effect, effect)
    }

    /// 中身を横一列に並べたカプセル。
    static func capsule(_ views: [NSView], horizontalPadding: CGFloat = 3) -> NSView {
        let (panel, host) = make(cornerRadius: ChromeSpec.capsuleHeight / 2)
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = ChromeSpec.itemSpacing
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(row)
        panel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            panel.heightAnchor.constraint(equalToConstant: ChromeSpec.capsuleHeight),
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: horizontalPadding),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -horizontalPadding),
            row.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        ])
        return panel
    }
}

/// カプセル内のボーダーレスなアイコンボタン。
final class ChromeButton: NSButton {
    private var handler: (() -> Void)?

    init(symbol: String, toolTip: String, identifier: String? = nil, handler: @escaping () -> Void) {
        super.init(frame: .zero)
        self.handler = handler
        let config = NSImage.SymbolConfiguration(pointSize: ChromeSpec.iconPointSize, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        isBordered = false
        contentTintColor = .labelColor.withAlphaComponent(0.75)
        self.toolTip = toolTip
        target = self
        action = #selector(pressed)
        if let identifier { setAccessibilityIdentifier(identifier) }
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: ChromeSpec.buttonSize).isActive = true
        heightAnchor.constraint(equalToConstant: ChromeSpec.buttonSize).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func pressed() { handler?() }
}

/// Edit（鉛筆）| Preview（目）の 2 分割スイッチ。両方のモードが常に見えていて、選択中の側が塗られる。
@MainActor
final class ModeSwitch: NSView {
    var onSelect: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private let selection = NSView()
    private var selectionLeading: NSLayoutConstraint?
    private(set) var selectedIndex = 0
    private static let segmentWidth: CGFloat = 32
    private static let height: CGFloat = ChromeSpec.capsuleHeight - 4

    init(items: [(title: String, symbol: String)]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        selection.wantsLayer = true
        selection.layer?.cornerRadius = ModeSwitch.height / 2
        selection.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selection)

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 0
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        for (index, item) in items.enumerated() {
            // アイコンのみ。名前はツールチップとアクセシビリティで伝える
            let button = NSButton(title: "", target: self, action: #selector(pressed(_:)))
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            button.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
                .withSymbolConfiguration(config)
            button.imagePosition = .imageOnly
            button.toolTip = "\(item.title) (⌘E to switch)"
            button.setAccessibilityLabel(item.title)
            button.isBordered = false
            button.tag = index
            button.widthAnchor.constraint(equalToConstant: ModeSwitch.segmentWidth).isActive = true
            button.setAccessibilityIdentifier("mode.\(item.title.lowercased())")
            buttons.append(button)
            row.addArrangedSubview(button)
        }

        let segmentWidth = ModeSwitch.segmentWidth
        let leading = selection.leadingAnchor.constraint(equalTo: leadingAnchor)
        selectionLeading = leading
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: segmentWidth * CGFloat(items.count)),
            heightAnchor.constraint(equalToConstant: ModeSwitch.height),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            leading,
            selection.widthAnchor.constraint(equalToConstant: segmentWidth),
            selection.topAnchor.constraint(equalTo: topAnchor), selection.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityIdentifier("modeControl")
        select(0, animated: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() { refreshColors() }
    override var wantsUpdateLayer: Bool { true }

    func select(_ index: Int, animated: Bool = true) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        let target = CGFloat(index) * ModeSwitch.segmentWidth
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                selectionLeading?.animator().constant = target
            }
        } else {
            selectionLeading?.constant = target
        }
        refreshColors()
    }

    private func refreshColors() {
        selection.layer?.backgroundColor = AppAccent.softFill.cgColor
        for (index, button) in buttons.enumerated() {
            let active = index == selectedIndex
            button.contentTintColor = active ? .labelColor : .tertiaryLabelColor
        }
    }

    @objc private func pressed(_ sender: NSButton) {
        guard sender.tag != selectedIndex else { return }
        onSelect?(sender.tag)
    }
}

/// ウィンドウ上に浮かぶ操作群。標準のツールバーやステータスバーは使わず、本文の上に重ねる。
///
///     ◧ ファイル名            [B I </> 🔗 …]（編集時のみ）              🔍  [Preview | Edit]
///     …本文…
///     [A ──●── A 125%]                                              [~782 tokens · 618 words]
@MainActor
final class FloatingChrome {
    struct Actions {
        var toggleSidebar: () -> Void = {}
        var find: () -> Void = {}
        var selectEditing: (Bool) -> Void = { _ in }
        var format: (Int) -> Void = { _ in }
    }

    var actions = Actions()

    private let titleLabel = PathTitleLabel(labelWithString: "")
    let updateIndicator = UpdateIndicator()
    private let modeSwitch = ModeSwitch(items: [("Edit", "square.and.pencil"), ("Preview", "eye")])  // 並びは Edit | Preview

    private var formatGroup: NSView!
    private var toolsGroup: NSView!
    private var modeGroup: NSView!
    private var sidebarCapsule: NSView!
    private var titleLeading: NSLayoutConstraint!
    private var titleYieldsToFormat: NSLayoutConstraint!
    private var topCenterConstraints: [NSLayoutConstraint] = []
    private weak var root: NSView?

    /// 書式ボタンとして出す FormatItem.all の添字
    private static let formatIndexes = [0, 1, 5, 6, 7, 14, 15, 16]

    func install(in root: NSView) {
        self.root = root

        // 左上: サイドバー切替 + ファイル名
        let sidebarButton = ChromeButton(symbol: "sidebar.leading", toolTip: "Show or hide the outline (⌃⌘S)",
                                         identifier: "sidebarToggle") { [weak self] in self?.actions.toggleSidebar() }
        sidebarCapsule = Glass.capsule([sidebarButton], horizontalPadding: 1)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 上部中央: 書式（編集時のみ）
        let formatButtons = Self.formatIndexes.map { index in
            ChromeButton(symbol: FormatItem.all[index].symbol ?? "textformat", toolTip: FormatItem.all[index].title) {
                [weak self] in self?.actions.format(index)
            }
        }
        formatGroup = Glass.capsule(formatButtons, horizontalPadding: 4)

        // 右上: 検索と、モード切替
        let findButton = ChromeButton(symbol: "magnifyingglass", toolTip: "Find (⌘F)", identifier: "chromeFind") {
            [weak self] in self?.actions.find()
        }
        toolsGroup = Glass.capsule([findButton], horizontalPadding: 1)
        modeSwitch.onSelect = { [weak self] index in self?.actions.selectEditing(index == 0) }
        modeGroup = Glass.capsule([modeSwitch], horizontalPadding: 2)

        for view in [sidebarCapsule!, titleLabel, updateIndicator, formatGroup!, toolsGroup!, modeGroup!] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        let inset = ChromeSpec.windowInset
        let topRow: [NSView] = [sidebarCapsule, titleLabel, updateIndicator, formatGroup, toolsGroup, modeGroup]
        topCenterConstraints = topRow.map { $0.centerYAnchor.constraint(equalTo: root.topAnchor, constant: 19) }
        titleLeading = titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.titleLeadingClosed)
        // 書式カプセルが出ているあいだだけ、ファイル名はその手前で止める（隠れているときは右の検索ボタンまで使える）
        titleYieldsToFormat = titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: formatGroup.leadingAnchor, constant: -ChromeSpec.groupSpacing)
        NSLayoutConstraint.activate(topCenterConstraints + [
            sidebarCapsule.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: ChromeSpec.trafficLightClearance),
            titleLeading,
            modeGroup.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            toolsGroup.trailingAnchor.constraint(equalTo: modeGroup.leadingAnchor, constant: -ChromeSpec.groupSpacing),
            formatGroup.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            updateIndicator.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            updateIndicator.trailingAnchor.constraint(lessThanOrEqualTo: toolsGroup.leadingAnchor, constant: -ChromeSpec.groupSpacing),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toolsGroup.leadingAnchor, constant: -ChromeSpec.groupSpacing),
        ])
    }

    /// 上段のカプセルを、信号ボタンと同じ高さ（ウィンドウ上端からの距離）に揃える。
    func alignTopRow(centerFromTop: CGFloat) {
        topCenterConstraints.forEach { $0.constant = centerFromTop }
    }

    private static let titleLeadingClosed = ChromeSpec.trafficLightClearance + ChromeSpec.capsuleHeight + 12

    func setTitle(_ title: String, fileURL: URL?) {
        titleLabel.stringValue = title
        titleLabel.fileURL = fileURL
        titleLabel.toolTip = fileURL.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    }

    /// サイドバーが開いているあいだ、ファイル名は本文側の左端へ寄せる（メモや Finder と同じ並び）。
    func setSidebarOpen(_ isOpen: Bool, animated: Bool) {
        let target = isOpen ? max(Self.titleLeadingClosed, ChromeSpec.sidebarWidth + 16) : Self.titleLeadingClosed
        if animated { titleLeading.animator().constant = target } else { titleLeading.constant = target }
    }

    func setMode(isEditing: Bool) {
        modeSwitch.select(isEditing ? 0 : 1)
        formatGroup.isHidden = !isEditing
        titleYieldsToFormat.isActive = !formatGroup.isHidden
    }

    /// 幅が足りないときは中央の書式カプセルを畳む（メニューとショートカットは引き続き使える）。
    func layoutForWidth(_ width: CGFloat, isEditing: Bool) {
        formatGroup.isHidden = !isEditing || width < 760
        titleYieldsToFormat.isActive = !formatGroup.isHidden
        titleLabel.isHidden = width < 520
        // 編集時は中央の書式カプセルと場所を取り合うので、幅に余裕があるときだけ出す
        updateIndicator.alphaValue = (isEditing && width < 1000) || width < 640 ? 0 : 1
    }

}

/// 上段のカプセルの背後に敷く、半透明（すりガラス）のヘッダ帯。スクロールした本文とカプセルが直接重ならないようにする。
/// クリックは受けない（ウィンドウのドラッグはタイトルバー領域として従来どおり効く）。
final class HeaderBackdropView: NSVisualEffectView {
    private let hairline = NSBox()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .headerView
        blendingMode = .withinWindow
        state = .followsWindowActiveState
        hairline.boxType = .separator
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// ヘッダのファイル名の右に出す更新表示。外部からの上書きを反映した瞬間はアクセント色のピルで目立たせ、
/// 数秒後に控えめな文字へ落ち着かせる（最後に更新された時刻は残す）。クリックで変更箇所へ移動する。
@MainActor
final class UpdateIndicator: NSView {
    var onClick: (() -> Void)?
    /// ピル右端の × 。変更の印を消す
    var onDismiss: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let dismissButton = NSButton()
    private var calmWork: DispatchWorkItem?
    private var isFresh = false
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9  // 高さ 18pt の半分。完全な丸端のピルにする
        icon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9.5, weight: .semibold))
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.init(100), for: .horizontal)

        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Hide change marks")?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold))
        dismissButton.isBordered = false
        dismissButton.imagePosition = .imageOnly
        dismissButton.target = self
        dismissButton.action = #selector(dismissPressed)
        dismissButton.toolTip = "Hide the change marks"
        dismissButton.setAccessibilityIdentifier("dismissChanges")
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.widthAnchor.constraint(equalToConstant: 13).isActive = true
        dismissButton.heightAnchor.constraint(equalToConstant: 13).isActive = true

        let row = NSStackView(views: [icon, label, dismissButton])
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY
        row.setCustomSpacing(6, after: label)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 18),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isHidden = true
        toolTip = "Jump to the latest change"
        setAccessibilityIdentifier("updateIndicator")
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { applyColors() }

    /// changes: 変わったブロック数（分からなければ nil）
    func showUpdate(changes: Int?, at date: Date = Date()) {
        var text = "Updated \(Self.timeFormatter.string(from: date))"
        if let changes, changes > 0 { text += changes == 1 ? " · 1 change" : " · \(changes) changes" }
        label.stringValue = text
        isHidden = false
        isFresh = true
        applyColors()
        calmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isFresh = false
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.8
                context.allowsImplicitAnimation = true
                self.applyColors()
            }
        }
        calmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func applyColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = AppAccent.Update.accent(dark: isDark)
        // 落ち着いた後もピルのまま。素の文字に戻すとヘッダの文字列に埋もれて見落とす
        layer?.backgroundColor = (isFresh ? AppAccent.Update.background(dark: isDark)
                                          : AppAccent.Update.calmBackground(dark: isDark)).cgColor
        label.textColor = isFresh ? AppAccent.Update.text(dark: isDark) : AppAccent.Update.calmText(dark: isDark)
        // アイコンは同じ色のまま残す（本文に残っている変更箇所の印と結びつけるため）
        icon.contentTintColor = accent
        dismissButton.contentTintColor = (isFresh ? AppAccent.Update.text(dark: isDark)
                                                  : AppAccent.Update.calmText(dark: isDark)).withAlphaComponent(0.7)
    }

    @objc private func dismissPressed() {
        calmWork?.cancel()
        isHidden = true
        isFresh = false
        onDismiss?()
    }

    @objc private func clicked() { onClick?() }
}

/// ヘッダのファイル名。標準のタイトルバー（タイトル + プロキシアイコン）の役割を兼ねる:
/// ⌘+クリック / 右クリックでパスのメニューを出して選んだ階層を Finder で開き、ドラッグするとファイルそのものを
/// 運べる（Finder へ落とせば移動、⌥ でコピー、ターミナルへ落とせばパス）。ウィンドウの移動はヘッダの余白で行う。
final class PathTitleLabel: NSTextField, NSDraggingSource {
    var fileURL: URL?
    private var mouseDownEvent: NSEvent?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            showPathMenu(with: event)
        } else if fileURL == nil {
            window?.performDrag(with: event)  // 未保存の文書には運ぶファイルが無い
        } else {
            mouseDownEvent = event
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent, let fileURL else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x,
                             event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        mouseDownEvent = nil

        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        icon.size = NSSize(width: 32, height: 32)
        let point = convert(start.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32), contents: icon)
        beginDraggingSession(with: [item], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) { mouseDownEvent = nil }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .link, .generic]
    }

    override func rightMouseDown(with event: NSEvent) { showPathMenu(with: event) }

    private func showPathMenu(with event: NSEvent) {
        guard let fileURL else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for url in PathBreadcrumb.components(of: fileURL) {
            let item = NSMenuItem(title: Self.displayName(of: url), action: #selector(openInFinder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        // 標準のタイトルバーと同じく、ラベルのすぐ下に先頭の項目（ファイル自身）が重なる位置へ出す
        let origin = NSPoint(x: -22, y: isFlipped ? bounds.maxY + 4 : bounds.minY - 4)
        menu.popUp(positioning: nil, at: origin, in: self)
    }

    private static func displayName(of url: URL) -> String {
        if url.path == "/" {
            return (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "/"
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    @objc private func openInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if url == fileURL?.standardizedFileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])  // ファイル自身は、選択した状態で表示する
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
