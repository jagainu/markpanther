import AppKit
import MarkPantherCore

/// プレビュー用の検索バー（エディタは NSTextView 標準の検索バーを使う）。
@MainActor
final class FindBar: NSView, NSSearchFieldDelegate {
    var onSearch: ((_ query: String, _ backwards: Bool) -> Void)?
    var onClose: (() -> Void)?

    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let stepper = NSSegmentedControl(images: [
        NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!,
        NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!,
    ], trackingMode: .momentary, target: nil, action: nil)

    init() {
        super.init(frame: .zero)
        searchField.placeholderString = "Find in preview"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.setAccessibilityIdentifier("previewFind")
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setAccessibilityIdentifier("previewFindCount")
        stepper.target = self
        stepper.action = #selector(step(_:))
        stepper.controlSize = .small
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.controlSize = .small

        // 背景はヘッダ帯と同じすりガラス。透明だとスクロールした本文と重なって読めない
        let backdrop = NSVisualEffectView()
        backdrop.material = .headerView
        backdrop.blendingMode = .withinWindow
        backdrop.state = .followsWindowActiveState
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor), backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        // 操作は右へ寄せる（Safari の検索バーと同じ並び）
        let row = NSStackView(views: [NSView(), searchField, countLabel, stepper, done])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 5, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var query: String { searchField.stringValue }

    func focus(prefill: String? = nil) {
        if let prefill, !prefill.isEmpty { searchField.stringValue = prefill }
        window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func show(current: Int, total: Int) {
        countLabel.stringValue = query.isEmpty ? "" : (total == 0 ? "Not found" : "\(current)/\(total)")
        countLabel.textColor = total == 0 && !query.isEmpty ? .systemRed : .secondaryLabelColor
    }

    func controlTextDidChange(_ notification: Notification) { onSearch?(query, false) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onSearch?(query, NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    @objc private func step(_ sender: NSSegmentedControl) { onSearch?(query, sender.selectedSegment == 0) }
    @objc private func close() { onClose?() }
}
