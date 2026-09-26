import Foundation
import MarkPantherCore
import WebKit

/// `markp://` でバンドル内リソース・ユーザー CSS・ローカル画像だけを配信する。Web 側に file:// は渡さない。
///
/// 本体と Quick Look 拡張の両方から使う。`Bundle.main` は拡張の中では拡張自身を指すので、
/// どちらのバンドルでも `preview/` を同梱しておけばそのまま正しく引ける。
/// ユーザー CSS は本体だけの機能なので、拡張には存在しないディレクトリが渡る（読めずに静かに失敗する）。
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    private let resolver: AssetResolver

    init(stylesDirectory: URL) {
        resolver = AssetResolver(stylesDirectory: stylesDirectory)
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let fileURL = fileURL(for: url),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = AssetResolver.mimeType(forPathExtension: fileURL.pathExtension)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func fileURL(for url: URL) -> URL? {
        switch resolver.resolve(url) {
        case .bundled(let relativePath):
            return Bundle.main.resourceURL?.appendingPathComponent("preview").appendingPathComponent(relativePath)
        case .userStyle(let fileURL), .localImage(let fileURL):
            return fileURL
        case nil:
            return nil
        }
    }
}
