import AppKit
import MarkPantherCore

/// 本文の下の細いフッタ。右に統計（トークン概算・語数）とズーム。
@MainActor
final class StatusBar: NSView {
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onZoomReset: (() -> Void)?
    /// スライダーを動かしたとき（倍率 0.5...3.0）
    var onZoomChange: ((CGFloat) -> Void)?

    static let height: CGFloat = 26

    var showsStats = true {
        didSet { statsRow.isHidden = !showsStats }
    }

    private let tokensLabel = PillLabel()
    private let wordsLabel = NSTextField(labelWithString: "")
    private let zoomSlider = NSSlider(value: 0, minValue: -1, maxValue: log2(3), target: nil, action: nil)
    private let zoomLabel = NSButton(title: "100%", target: nil, action: nil)
    private let statsRow = NSStackView()

    init() {
        super.init(frame: .zero)

        let zoomOut = iconButton("textformat.size.smaller", "Zoom out (⌘−)", #selector(zoomOutPressed))
        let zoomIn = iconButton("textformat.size.larger", "Zoom in (⌘+)", #selector(zoomInPressed))

        wordsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        wordsLabel.textColor = .secondaryLabelColor
        wordsLabel.setAccessibilityIdentifier("statusWords")
        tokensLabel.setAccessibilityIdentifier("statusTokens")

        zoomLabel.isBordered = false
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.contentTintColor = .secondaryLabelColor
        zoomLabel.target = self
        zoomLabel.action = #selector(zoomResetPressed)
        zoomLabel.toolTip = "Actual size (⌘0)"
        zoomLabel.setAccessibilityIdentifier("statusZoom")
        zoomLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true

        // 倍率は対数目盛り（50%〜300% で 100% が左に寄りすぎないように）
        zoomSlider.controlSize = .mini
        zoomSlider.isContinuous = true
        zoomSlider.target = self
        zoomSlider.action = #selector(zoomSliderChanged)
        zoomSlider.toolTip = "Zoom"
        zoomSlider.setAccessibilityIdentifier("statusZoomSlider")
        zoomSlider.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let divider = NSBox()
        divider.boxType = .separator
        divider.heightAnchor.constraint(equalToConstant: 12).isActive = true
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        statsRow.orientation = .horizontal
        statsRow.alignment = .centerY
        statsRow.spacing = 10
        statsRow.setViews([tokensLabel, wordsLabel, divider], in: .trailing)

        let row = NSStackView(views: [NSView(), statsRow, zoomOut, zoomSlider, zoomIn, zoomLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStats(_ stats: TextStats) {
        tokensLabel.stringValue = TextStats.formatTokens(stats.approximateTokens)
        wordsLabel.stringValue = "\(stats.words.formatted()) words"
    }

    func setZoom(_ zoom: CGFloat) {
        zoomLabel.title = "\(Int((zoom * 100).rounded()))%"
        zoomSlider.doubleValue = log2(Double(zoom))
    }

    private func iconButton(_ symbol: String, _ toolTip: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)!
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = toolTip
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    @objc private func zoomInPressed() { onZoomIn?() }
    @objc private func zoomOutPressed() { onZoomOut?() }
    @objc private func zoomResetPressed() { onZoomReset?() }

    @objc private func zoomSliderChanged() {
        var zoom = pow(2, zoomSlider.doubleValue)
        if abs(zoom - 1) < 0.04 { zoom = 1 }  // 100% 付近で吸着
        onZoomChange?(CGFloat((zoom * 20).rounded() / 20))  // 5% 刻み
    }
}

/// トークン概算を入れる、角丸の小さなラベル。文字は枠の中央に置き、隣のラベルとベースラインを揃える。
private final class PillLabel: NSView {
    private let label = NSTextField(labelWithString: "")

    var stringValue: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
    }

    override var firstBaselineOffsetFromTop: CGFloat {
        label.frame.minY > 0 ? bounds.height - label.frame.minY - label.firstBaselineOffsetFromTop : 12
    }
}
