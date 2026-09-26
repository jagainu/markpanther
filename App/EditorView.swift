import AppKit
import MarkPantherCore

/// 「Scroll past end」用に、末尾の下へ余白を足せる NSTextView。
final class MarkdownTextView: NSTextView {
    var scrollPastEnd = false

    override func setFrameSize(_ newSize: NSSize) {
        var size = newSize
        if scrollPastEnd, let scrollView = enclosingScrollView {
            size.height += (scrollView.contentSize.height * 0.6).rounded()
        }
        super.setFrameSize(size)
    }
}

@MainActor
final class EditorView: NSView, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
    let scrollView: NSScrollView
    let textView: MarkdownTextView
    var onTextChange: ((String) -> Void)?
    var onScrollLine: ((Int) -> Void)?
    /// 表示倍率（プレビューの pageZoom と揃える）。フォントサイズに掛ける。
    var zoom: CGFloat = 1 {
        didSet { if zoom != oldValue { applyPreferences() } }
    }

    private let highlighter = MarkdownHighlighter()
    private var assist = EditorAssist()
    private var formatter = MarkdownFormatter()
    private var baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private var isApplyingEdit = false
    private var isReplacingAll = false
    private var lineNumbers: LineNumberRulerView!

    override init(frame: NSRect) {
        scrollView = NSScrollView(frame: frame)
        let contentSize = scrollView.contentSize
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: contentSize.width, height: .greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        textView = MarkdownTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: container)
        super.init(frame: frame)

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = AppAccent.color
        textView.selectedTextAttributes = [.backgroundColor: AppAccent.textSelection]
        textView.delegate = self
        textView.setAccessibilityIdentifier("editor")
        storage.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        lineNumbers = LineNumberRulerView(textView: textView, scrollView: scrollView)
        scrollView.verticalRulerView = lineNumbers
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(updateInsets),
                                               name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        applyPreferences()
    }

    @objc private func didScroll() {
        guard !isHidden, onScrollLine != nil else { return }
        onScrollLine?(topVisibleLine())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 上下に浮いているクロームのぶんの余白。本文はその下をスクロールして通り抜ける。
    func setInsets(top: CGFloat, bottom: CGFloat) {
        scrollView.automaticallyAdjustsContentInsets = false
        let insets = NSEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        guard scrollView.contentInsets.top != top || scrollView.contentInsets.bottom != bottom else { return }
        let wasAtTop = scrollView.contentView.bounds.origin.y <= -scrollView.contentInsets.top + 1
        scrollView.contentInsets = insets
        scrollView.scrollerInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        if wasAtTop { scrollView.contentView.scroll(to: NSPoint(x: 0, y: -top)) }
    }

    // MARK: - Content

    var text: String { textView.string }

    /// 外部更新などで全文を差し替える。選択とスクロール位置はできる範囲で保つ。Undo 履歴は破棄する。
    func replaceAll(with newText: String) {
        guard newText != textView.string else { return }
        let selection = textView.selectedRange()
        let origin = scrollView.contentView.bounds.origin
        isReplacingAll = true
        textView.string = newText
        isReplacingAll = false
        lineNumbers.invalidateLineNumbers()
        textView.undoManager?.removeAllActions()
        let length = (newText as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func applyPreferences() {
        let p = Preferences.shared
        let size = (CGFloat(p.fontSize) * zoom).rounded()
        baseFont = NSFont(name: p.fontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        textView.scrollPastEnd = p.scrollPastEnd

        assist.autoCompleteBrackets = p.autoCompleteBrackets
        assist.autoInsertLinePrefix = p.autoInsertLinePrefix
        assist.autoIncrementOrderedList = p.autoIncrementOrderedList
        assist.insertSpacesForTab = p.insertSpacesForTab
        assist.tabWidth = p.tabWidth
        formatter = MarkdownFormatter(listMarker: p.listMarker,
                                      indentUnit: p.insertSpacesForTab ? String(repeating: " ", count: p.tabWidth) : "\t")

        lineNumbers.fontSize = max(9, (size * 0.9).rounded())
        textView.typingAttributes = baseAttributes
        updateInsets()
        rehighlightAll()
        textView.setFrameSize(textView.frame.size)
    }

    // MARK: - Formatting

    func perform(_ command: FormatCommand) {
        guard let edit = formatter.apply(command, to: textView.string, selection: textView.selectedRange()) else { return }
        apply(edit)
    }

    private func apply(_ edit: TextEdit) {
        isApplyingEdit = true
        defer { isApplyingEdit = false }
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
    }

    // MARK: - Line mapping（モード切替時の位置引き継ぎ）

    /// 表示領域の上端にある行（0 始まり）
    func topVisibleLine() -> Int {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return 0 }
        var rect = scrollView.contentView.bounds
        rect.origin.y += scrollView.contentInsets.top  // クロームの下に隠れているぶんは「見えている先頭」に数えない
        rect.origin.y -= textView.textContainerOrigin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: container)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphs.location)
        let prefix = (textView.string as NSString).substring(to: min(charIndex, (textView.string as NSString).length))
        return prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
    }

    func scroll(toLine line: Int) {
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        let string = textView.string as NSString
        var index = 0
        var current = 0
        while current < line, index < string.length {
            let lineRange = string.lineRange(for: NSRange(location: index, length: 0))
            index = NSMaxRange(lineRange)
            current += 1
        }
        layoutManager.ensureLayout(for: container)
        let glyph = layoutManager.glyphIndexForCharacter(at: min(index, max(string.length - 1, 0)))
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let y = line == 0 ? 0 : lineRect.minY + textView.textContainerOrigin.y
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y - scrollView.contentInsets.top))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        guard !isApplyingEdit, !textView.hasMarkedText(), let replacementString,
              textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true,
              let edit = assist.intercept(text: textView.string, range: range, replacement: replacementString)
        else { return true }
        apply(edit)
        return false
    }

    func textDidChange(_ notification: Notification) {
        guard !isReplacingAll else { return }
        onTextChange?(textView.string)
    }

    // MARK: - Highlighting

    /// 必ず willProcessEditing で行う。NSTextStorage はこの直後に fixAttributes で「フォントに無い文字」
    /// （日本語など）を代替フォントへ差し替える。didProcessEditing で .font を上書きすると、その差し替えを
    /// 潰してしまい、等幅フォントにグリフの無い文字が描画されなくなる。
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let text = textStorage.string
        let range = isReplacingAll
            ? NSRange(location: 0, length: textStorage.length)
            : highlighter.rangeToRehighlight(in: text, editedRange: editedRange)
        applyHighlight(to: textStorage, range: range)
    }

    private func rehighlightAll() {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        applyHighlight(to: storage, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
    }

    private func applyHighlight(to storage: NSTextStorage, range: NSRange) {
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        storage.setAttributes(baseAttributes, range: range)
        for span in highlighter.highlight(storage.string, in: range) {
            let spanRange = NSIntersectionRange(span.range, range)
            guard spanRange.length > 0 else { continue }
            storage.addAttributes(attributes(for: span.style), range: spanRange)
        }
    }

    /// 行の高さは固定にする。日本語などは代替フォント（ヒラギノ）で描かれ、そのままだとその行だけ背が高くなって
    /// 行間が不揃いになる（行番号の間隔も揃わない）。固定値は「基準フォントの行高 + 行間の設定」。
    private var baseAttributes: [NSAttributedString.Key: Any] {
        let natural = (textView.layoutManager?.defaultLineHeight(for: baseFont) ?? baseFont.pointSize * 1.2).rounded(.up)
        let lineHeight = natural + CGFloat(Preferences.shared.lineSpacing)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return [
            .font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph,
            // 固定した行の中で文字が下に寄らないよう、増やした分の半分だけ持ち上げる
            .baselineOffset: ((lineHeight - natural) / 2).rounded(.down),
        ]
    }

    private func font(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(baseFont.fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    private func attributes(for style: HighlightStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .heading:
            return [.font: font(.bold), .foregroundColor: EditorPalette.heading]
        case .strong:
            return [.font: font(.bold)]
        case .emphasis:
            return [.font: font(.italic)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor]
        case .highlight:
            return [.backgroundColor: EditorPalette.markBackground]
        case .inlineCode:
            return [.foregroundColor: EditorPalette.code, .backgroundColor: EditorPalette.codeBackground]
        case .codeBlock:
            return [.foregroundColor: EditorPalette.code]
        case .codeFence:
            return [.foregroundColor: EditorPalette.markup]
        case .codeLanguage:
            return [.foregroundColor: EditorPalette.keyword, .font: font(.bold)]
        case .link:
            return [.foregroundColor: EditorPalette.link, .underlineStyle: NSUnderlineStyle.single.rawValue]
        case .image:
            return [.foregroundColor: EditorPalette.keyword]
        case .linkURL:
            return [.foregroundColor: EditorPalette.url]
        case .blockquote:
            return [.foregroundColor: EditorPalette.quote]
        case .listMarker:
            return [.foregroundColor: EditorPalette.list, .font: font(.bold)]
        case .taskMarker:
            return [.foregroundColor: EditorPalette.keyword, .font: font(.bold)]
        case .tableMarkup:
            return [.foregroundColor: EditorPalette.table]
        case .tableHeader:
            return [.font: font(.bold)]
        case .htmlTag:
            return [.foregroundColor: EditorPalette.html]
        case .footnote:
            return [.foregroundColor: EditorPalette.table]
        case .math:
            return [.foregroundColor: EditorPalette.math]
        case .tocToken:
            return [.foregroundColor: EditorPalette.keyword, .font: font(.bold)]
        case .hardBreak:
            return [.backgroundColor: EditorPalette.codeBackground]
        case .escape:
            return [.foregroundColor: EditorPalette.markup]
        case .horizontalRule, .markup:
            return [.foregroundColor: EditorPalette.markup]
        case .frontmatter:
            return [.foregroundColor: EditorPalette.frontmatter]
        case .htmlComment:
            return [.foregroundColor: EditorPalette.comment, .font: font(.italic)]
        }
    }

    // MARK: - Layout

    /// プレビューと同じ横位置に本文を置くための値（preview.css / styles の #content と対応）:
    /// 本文の開始 = 左から 75pt。表示幅が「最大幅 860pt × 倍率」を超えたら、超えた分の半分だけ中央へ寄せる。
    private static let previewTextStart: CGFloat = 75
    private static let previewMaxWidth: CGFloat = 860

    @objc private func updateInsets() {
        let p = Preferences.shared
        let fullWidth = scrollView.frame.width
        let centering = max(0, (fullWidth - Self.previewMaxWidth * zoom) / 2)
        let padding = textView.textContainer?.lineFragmentPadding ?? 5
        // 本文の開始位置 = 行番号の欄 + 余白 + lineFragmentPadding
        var horizontal = max(CGFloat(p.horizontalInset),
                             Self.previewTextStart + centering - lineNumbers.ruleThickness - padding)
        if p.limitEditorWidth {
            let extra = (scrollView.contentSize.width - CGFloat(p.editorMaxWidth)) / 2
            horizontal = max(horizontal, extra.rounded())
        }
        let inset = NSSize(width: horizontal, height: CGFloat(p.verticalInset))
        if textView.textContainerInset != inset { textView.textContainerInset = inset }
    }
}

/// エディタの配色。CotEditor のように要素の種類ごとに色相を分ける。ライト/ダークで自動切替。
private enum EditorPalette {
    static let heading = dynamic(light: 0x0B5FB0, dark: 0x6CB6FF)
    static let keyword = dynamic(light: 0x8A3FC7, dark: 0xC792EA)
    static let code = dynamic(light: 0xB3401C, dark: 0xF5A97F)
    static let link = dynamic(light: 0x0969DA, dark: 0x79B8FF)
    static let url = dynamic(light: 0x5B7C99, dark: 0x8AA4BD)
    static let quote = dynamic(light: 0x2E7D32, dark: 0x8FD18A)
    static let list = dynamic(light: 0xD9730D, dark: 0xFFB454)
    static let table = dynamic(light: 0x00838F, dark: 0x5CCFE6)
    static let html = dynamic(light: 0xA31573, dark: 0xF78FC7)
    static let math = dynamic(light: 0x6F42C1, dark: 0xB392F0)
    static let comment = dynamic(light: 0x6A737D, dark: 0x8B949E)
    static let frontmatter = dynamic(light: 0x7A6A3A, dark: 0xC9B97A)
    static let markup = NSColor.tertiaryLabelColor
    static let markBackground = NSColor.systemYellow.withAlphaComponent(0.32)
    static let codeBackground = dynamic(light: 0x8C959F, dark: 0x8C959F, alpha: 0.16)

    private static func dynamic(light: Int, dark: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
    }
}
