// .md の書類アイコン（App/MarkdownDocument.icns）を作る。
//   swift design/make-document-icon.swift
// 紙は自前で描く（OS の書類アイコンの絵は同梱しない）。パンサーは design/DocumentIcon-panther.png
// （AppIcon-artwork.png の背景を抜いたもの）。大きさごとに描き分ける: 32pt 以下は md を大きく、16pt は md だけ。
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.first!).deletingLastPathComponent().deletingLastPathComponent()
let panther = NSImage(contentsOf: root.appendingPathComponent("design/DocumentIcon-panther.png"))!
let pink = NSColor(srgbRed: 0.76, green: 0.17, blue: 0.31, alpha: 1)

/// 紙の外形（上からの割合）。右上を折り返す
enum Paper {
    static let left: CGFloat = 0.164, right: CGFloat = 0.834, top: CGFloat = 0.057, bottom: CGFloat = 0.941
    static let fold: CGFloat = 0.27   // 折り返しの一辺
    static let radius: CGFloat = 0.035
}

/// S: 描く大きさ（pt）。レイアウトはこれで決め、実際の画素数は scale 倍
func drawIcon(points S: CGFloat) {
    let small = S <= 16, mid = S <= 32
    // 16pt は md を大きく入れるため、紙を少し広く、折り返しを小さくする
    let L = S * (small ? 0.13 : Paper.left), R = S * (small ? 0.87 : Paper.right)
    let T = S * (small ? 0.04 : Paper.top), B = S * (small ? 0.96 : Paper.bottom)
    let f = S * (small ? 0.24 : Paper.fold), r = S * (small ? 0.07 : Paper.radius)

    // 紙の外形（flipped 座標: 上が 0）
    let body = NSBezierPath()
    body.move(to: NSPoint(x: L + r, y: T))
    body.line(to: NSPoint(x: R - f, y: T))
    body.line(to: NSPoint(x: R, y: T + f))
    body.line(to: NSPoint(x: R, y: B - r))
    body.appendArc(from: NSPoint(x: R, y: B), to: NSPoint(x: R - r, y: B), radius: r)
    body.line(to: NSPoint(x: L + r, y: B))
    body.appendArc(from: NSPoint(x: L, y: B), to: NSPoint(x: L, y: B - r), radius: r)
    body.line(to: NSPoint(x: L, y: T + r))
    body.appendArc(from: NSPoint(x: L, y: T), to: NSPoint(x: L + r, y: T), radius: r)
    body.close()

    // 落ち影
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowBlurRadius = max(1, S * 0.012)
    shadow.shadowOffset = NSSize(width: 0, height: -S * 0.006)
    shadow.set()
    NSColor.white.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 紙の面: ごく淡いグレーのグラデーション
    NSGradient(starting: NSColor(white: 0.975, alpha: 1), ending: NSColor(white: 0.925, alpha: 1))!
        .draw(in: body, angle: -60)

    // 小さいサイズは影だけだと紙の縁が背景に溶けるので、細い輪郭を足す
    if mid {
        NSColor(white: 0.62, alpha: 1).setStroke()
        body.lineWidth = 0.5
        body.stroke()
    }

    // 折り返し: 切り欠いた角が、左下に直角をもつ三角形として紙の上に折り重なる（角は少し丸める）
    let fr = S * 0.03
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: R - f, y: T))
    flap.line(to: NSPoint(x: R, y: T + f))
    flap.line(to: NSPoint(x: R - f + fr, y: T + f))
    flap.appendArc(from: NSPoint(x: R - f, y: T + f), to: NSPoint(x: R - f, y: T + f - fr), radius: fr)
    flap.close()
    NSGraphicsContext.saveGraphicsState()
    let flapShadow = NSShadow()
    flapShadow.shadowColor = NSColor(white: 0, alpha: 0.32)
    flapShadow.shadowBlurRadius = max(1, S * 0.025)
    flapShadow.shadowOffset = NSSize(width: -S * 0.006, height: -S * 0.012)
    flapShadow.set()
    NSColor.white.setFill()
    flap.fill()
    NSGraphicsContext.restoreGraphicsState()
    // 裏面: 折り目（斜めの辺）側が明るく、直角の角に向かって少し陰る
    NSGradient(starting: NSColor(white: 1.0, alpha: 1), ending: NSColor(white: 0.88, alpha: 1))!
        .draw(in: flap, angle: 45)

    // パンサー（折り返しの下に収める）と md
    if !small {
        let w = S * 0.28, h = w * panther.size.height / panther.size.width
        let top = S * (mid ? 0.40 : 0.41)
        panther.draw(in: NSRect(x: S * 0.5 - w / 2, y: top, width: w, height: h), from: .zero,
                     operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    let text = "md" as NSString
    if small {
        // 16pt（ヘッダやリスト表示）は md だけ。読めることを優先し、紙からはみ出す大きさで折り返しより下へ置く
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: S * 0.52, weight: .black),
                                                    .foregroundColor: pink, .kern: -S * 0.02]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (S - size.width) / 2, y: S * 0.62 - size.height / 2), withAttributes: attrs)
        return
    }
    let fontSize = S * (mid ? 0.30 : 0.15)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
                                                .foregroundColor: pink]
    let size = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (S - size.width) / 2, y: S * (mid ? 0.62 : 0.71)), withAttributes: attrs)
}

func png(points: CGFloat, scale: Int) -> Data {
    let px = Int(points) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // flipped（上が 0）で描く
    context.cgContext.translateBy(x: 0, y: points)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    drawIcon(points: points)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("MarkdownDocument.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! png(points: CGFloat(points), scale: scale).write(to: iconset.appendingPathComponent(name))
    }
}
let output = root.appendingPathComponent("App/MarkdownDocument.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
print("iconset: \(iconset.path)")
