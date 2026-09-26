import Foundation

/// The chain of locations from a file up to the volume root, used for the
/// path menu behind the window title.
public enum PathBreadcrumb {
    /// Starts at the file itself and walks up until it cannot go higher.
    ///
    /// 終了条件は「上に進めなくなったら」で、パス文字列の一致では見ない。相対 URL に
    /// 対する `deletingLastPathComponent()` は `../` を足し続けるため、パス比較で
    /// 打ち切る書き方だと永久に一致せず 100% CPU で回り続ける（2026-09-21 実機で発生）。
    public static func components(of fileURL: URL) -> [URL] {
        var result: [URL] = []
        // 相対 URL は先に絶対ファイル URL へ倒す（`../` が伸び続けるのを防ぐ）
        var url = URL(fileURLWithPath: fileURL.path).standardizedFileURL
        while true {
            result.append(url)
            let parent = url.deletingLastPathComponent().standardizedFileURL
            guard parent.pathComponents.count < url.pathComponents.count else { break }
            url = parent
        }
        return result
    }
}
