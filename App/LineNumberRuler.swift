import AppKit

/// エディタ左の行番号。振り方は CotEditor に合わせる: 細身の数字を右寄せし、本文 1 行目のベースラインに揃える。
/// 折り返した行は先頭の断片にだけ番号を出し、カーソルのある行は濃く表示する。区切り線は引かない。
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    /// 各行の先頭の文字位置（UTF-16）。テキストが変わるたびに作り直す
    private var lineStarts: [Int] = [0]
    private var needsLineStarts = true

    /// 番号の文字サイズ（本文より少し小さく）。細身・等幅数字のフォントはここから作る
    var fontSize: CGFloat = 12 {
        didSet {
            guard fontSize != oldValue else { return }
            font = Self.numberFont(size: fontSize, weight: .regular)
            currentFont = Self.numberFont(size: fontSize, weight: .semibold)
            invalidateLineNumbers()
        }
    }

    private var font = LineNumberRulerView.numberFont(size: 12, weight: .regular)
    private var currentFont = LineNumberRulerView.numberFont(size: 12, weight: .semibold)
    private static let trailingPadding: CGFloat = 6
    private static let leadingPadding: CGFloat = 10
    /// 番号の右端を、プレビューの行番号（preview.css の --markpanther-lno-right = 40px）と同じ位置に揃えるための最小幅
    static let minimumThickness: CGFloat = 48

    /// コンデンス幅のシステムフォント + 等幅数字（桁が変わっても右端が揃う）
    private static func numberFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
            ]],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = Self.minimumThickness
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: textView)
        center.addObserver(self, selector: #selector(redraw), name: NSTextView.didChangeSelectionNotification, object: textView)
        center.addObserver(self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
                           object: scrollView.contentView)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// テキストを外から丸ごと差し替えたとき（didChange 通知が飛ばない経路）にも呼ぶ。
    func invalidateLineNumbers() {
        needsLineStarts = true
        needsDisplay = true
    }

    @objc private func textChanged() { invalidateLineNumbers() }
    @objc private func redraw() { needsDisplay = true }

    private func rebuildLineStartsIfNeeded(_ string: NSString) {
        guard needsLineStarts else { return }
        needsLineStarts = false
        var starts = [0]
        var index = 0
        while index < string.length {
            index = NSMaxRange(string.lineRange(for: NSRange(location: index, length: 0)))
            if index < string.length || string.character(at: index - 1) == 0x0A { starts.append(index) }
        }
        lineStarts = starts
        // 桁数に合わせて幅を決める（最低 3 桁ぶん）
        let digits = max(3, String(starts.count).count)
        let width = (String(repeating: "8", count: digits) as NSString).size(withAttributes: [.font: font]).width
        let thickness = max(Self.minimumThickness, (width + Self.leadingPadding + Self.trailingPadding).rounded(.up))
        if abs(ruleThickness - thickness) > 0.5 { ruleThickness = thickness }
    }

    /// 文字位置 → 行番号（0 始まり）。二分探索。
    private func lineIndex(for location: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= location { low = mid } else { high = mid - 1 }
        }
        return low
    }

    override func draw(_ dirtyRect: NSRect) {
        // 標準のルーラーの背景（グレー + 罫線）は使わず、エディタと同じ地色のままにする
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let scrollView else { return }
        let string = textView.string as NSString
        rebuildLineStartsIfNeeded(string)

        let visible = scrollView.contentView.bounds
        let origin = textView.textContainerOrigin
        let currentLine = lineIndex(for: min(textView.selectedRange().location, string.length))
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let current: [NSAttributedString.Key: Any] = [.font: currentFont, .foregroundColor: NSColor.labelColor]
        let textFont = textView.font ?? font
        // 本文のベースライン（行の断片の上端からの距離）。エディタは行の高さを固定し、増やした分の半分だけ文字を
        // 持ち上げている（EditorView.baseAttributes）ので、同じ式で求める。グリフの位置から取ると、空行だけ値が
        // 変わって番号の間隔が不揃いになる。
        let natural = layoutManager.defaultLineHeight(for: textFont).rounded(.up)
        func baseline(in lineRect: NSRect) -> CGFloat {
            let lift = ((lineRect.height - natural) / 2).rounded(.down)
            return lineRect.height + textFont.descender - max(0, lift)
        }

        /// baseline: 行の断片の上端から本文のベースラインまでの距離
        func drawNumber(_ line: Int, lineRect: NSRect, baseline: CGFloat) {
            let text = "\(line + 1)" as NSString
            let isCurrent = line == currentLine
            let attributes = isCurrent ? current : normal
            let width = text.size(withAttributes: attributes).width
            // テキストビュー座標 → ルーラー座標。番号のベースラインを本文のベースラインに重ねる
            let top = convert(NSPoint(x: 0, y: lineRect.minY + origin.y + baseline), from: textView).y
                - (isCurrent ? currentFont : font).ascender
            text.draw(at: NSPoint(x: ruleThickness - width - Self.trailingPadding, y: top), withAttributes: attributes)
        }

        if string.length == 0 {
            let rect = NSRect(x: 0, y: 0, width: 0, height: natural)
            drawNumber(0, lineRect: rect, baseline: baseline(in: rect))
            return
        }

        var searchRect = visible
        searchRect.origin.y -= origin.y
        let glyphs = layoutManager.glyphRange(forBoundingRect: searchRect, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = lineIndex(for: characters.location)
        while line < lineStarts.count, lineStarts[line] <= NSMaxRange(characters) {
            let start = lineStarts[line]
            if start < string.length {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                drawNumber(line, lineRect: lineRect, baseline: baseline(in: lineRect))
            } else {
                // 末尾の空行（最後が改行で終わる文書）
                let extra = layoutManager.extraLineFragmentRect
                drawNumber(line, lineRect: extra, baseline: baseline(in: extra))
            }
            line += 1
        }
    }
}
