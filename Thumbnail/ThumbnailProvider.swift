import AppKit
import MarkPantherCore
import QuickLookThumbnailing

/// Draws the Finder icon for a Markdown file: a sheet of paper with the
/// document's title and opening lines.
///
/// Deliberately native drawing rather than the real renderer — a folder of
/// Markdown would otherwise start a web view per icon, and Quick Look gives a
/// thumbnail only a short moment to appear.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        let markdown = (try? String(contentsOf: request.fileURL, encoding: .utf8)) ?? ""
        let summary = ThumbnailSummary.make(from: markdown, maxLines: 14)
        let size = request.maximumSize

        handler(QLThumbnailReply(contextSize: size) { context in
            Self.draw(summary, in: CGRect(origin: .zero, size: size), context: context)
            return true
        }, nil)
    }

    // MARK: - Drawing

    private static let accent = NSColor(srgbRed: 0xC9 / 255, green: 0x44 / 255, blue: 0x5F / 255, alpha: 1)

    private static func draw(_ summary: ThumbnailSummary, in rect: CGRect, context: CGContext) {
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.white.setFill()
        rect.fill()

        // 紙の縁。小さいサイズでは線が潰れるので入れない
        if rect.width >= 64 {
            NSColor(white: 0.85, alpha: 1).setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
        }

        let margin = max(4, rect.width * 0.09)
        var cursor = rect.maxY - margin
        let width = rect.width - margin * 2
        // アイコンは正方形とは限らないので、文字の大きさは幅ではなく短辺で決める
        let unit = min(rect.width, rect.height)

        if let title = summary.title {
            let font = NSFont.boldSystemFont(ofSize: max(6, unit * 0.11))
            let height = drawText(title, at: CGPoint(x: rect.minX + margin, y: cursor),
                                  width: width, font: font, color: .black, maxLines: 2)
            cursor -= height + unit * 0.035

            // 見出しの下に、アプリと同じローズの罫
            accent.setFill()
            CGRect(x: rect.minX + margin, y: cursor, width: min(width, unit * 0.30),
                   height: max(1, unit * 0.015)).fill()
            cursor -= unit * 0.055
        }

        guard rect.height >= 48 else { return }

        let bodyFont = NSFont.systemFont(ofSize: max(5, unit * 0.075))
        for line in summary.lines {
            guard cursor > rect.minY + margin else { break }
            let height = drawText(line, at: CGPoint(x: rect.minX + margin, y: cursor),
                                  width: width, font: bodyFont, color: NSColor(white: 0.32, alpha: 1),
                                  maxLines: 1)
            cursor -= height + unit * 0.018
        }
    }

    /// Draws `text` with its TOP at `point.y` and returns the height used.
    private static func drawText(_ text: String, at point: CGPoint, width: CGFloat, font: NSFont,
                                 color: NSColor, maxLines: Int) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ]
        let height = ceil(font.ascender - font.descender) * CGFloat(maxLines)
        let box = CGRect(x: point.x, y: point.y - height, width: width, height: height)
        (text as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: attributes)
        return height
    }
}
