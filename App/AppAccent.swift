import AppKit

/// The app's accent, drawn from the icon's rose palette rather than the system accent.
///
/// macOS のシステムアクセントは利用者の設定（既定は青）なので、そのままだとアイコンと
/// ちぐはぐになる。挿入ポイント・行の選択・モード切替など、色で「いまここ」を示す場所は
/// すべてここから引いて、アイコンと同じ赤ピンクに揃える。
/// 数値はアイコンの原画（`design/AppIcon-artwork.png`）から拾ったバラ色を、
/// UI で読める濃さまで寄せたもの。
enum AppAccent {
    /// 線・記号・挿入ポイントなど、細い要素に使う濃さ。
    static let color = dynamic(light: 0xC9445F, dark: 0xF58BA5)

    /// 行の選択など、面で塗る場所。白抜きの文字が乗る前提の濃さ。
    static let selectionFill = dynamic(light: 0xC9445F, dark: 0xB03C57)

    /// 選択された面の上に乗る文字。
    static let onSelection = NSColor.white

    /// 押さえた背景（モード切替の選択ピルなど）。文字色は変えずに済む薄さ。
    static let softFill = dynamic(light: 0xC9445F, dark: 0xF58BA5, alpha: 0.16)

    /// テキスト選択の下地。挿入ポイントと同系で、文字が読める薄さ。
    static let textSelection = dynamic(light: 0xC9445F, dark: 0xF58BA5, alpha: 0.26)

    // MARK: - 「外部から更新された」表示

    /// プレビューの変更ハイライト（preview.css の `--markpanther-change-*`）と同じ値。
    /// ヘッダの Updated 表示と本文の印が同じものを指していると分かるように揃える。
    enum Update {
        static func accent(dark: Bool) -> NSColor { dark ? rgb(0xFF7AA8) : rgb(0xF0407F) }
        static func background(dark: Bool) -> NSColor { dark ? rgb(0xFF7AA8, 0.30) : rgb(0xFF528C, 0.24) }
        /// ピルの上でも読める濃さの同系色
        static func text(dark: Bool) -> NSColor { dark ? rgb(0xFFB3CC) : rgb(0xA3154F) }

        /// 数秒たって落ち着いた後。ピルの形は保ったまま主張だけ下げる
        /// （素の文字に戻すと、外から書き換わったこと自体を見落としやすい）。
        static func calmBackground(dark: Bool) -> NSColor { dark ? rgb(0xFF7AA8, 0.15) : rgb(0xFF528C, 0.12) }
        static func calmText(dark: Bool) -> NSColor { dark ? rgb(0xFFB3CC, 0.85) : rgb(0xA3154F, 0.78) }
    }

    // MARK: - Building blocks

    static func rgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// 外観の切り替えに自動で追従する色。呼び出し側が dark かどうかを知らなくて済む。
    private static func dynamic(light: Int, dark: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha)
        }
    }
}

/// Draws selected rows in the app's accent instead of the system one.
///
/// `NSTableView` の `.sourceList` / `.plain` はシステムアクセントで選択行を塗るため、
/// 行ビューを差し替えて自前で描く。
final class AccentRowView: NSTableRowView {
    /// セル側がこれを見て文字色を白へ切り替える。
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }

    /// サイドバーは `NSVisualEffectView` の上にあり、`.sourceList` の行は既定で vibrancy が効く。
    /// そのまま塗るとアクセントが背景と混ぜられて灰みがかり、白文字との差も痩せるので、
    /// この行だけ vibrancy を切って色をそのまま出す。
    override var allowsVibrancy: Bool { false }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        AppAccent.selectionFill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}
