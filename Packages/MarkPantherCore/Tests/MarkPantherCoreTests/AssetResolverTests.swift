import XCTest
@testable import MarkPantherCore

final class AssetResolverTests: XCTestCase {
    private let stylesDir = URL(fileURLWithPath: "/tmp/MarkPantherStyles")

    private func makeResolver() -> AssetResolver {
        AssetResolver(stylesDirectory: stylesDir)
    }

    // MARK: - bundled

    func test_bundled_resolvesRelativePath() {
        let url = URL(string: "markp://app/preview/index.html")!
        XCTAssertEqual(makeResolver().resolve(url), .bundled(relativePath: "preview/index.html"))
    }

    func test_bundled_singleFileAtRoot() {
        let url = URL(string: "markp://app/style.css")!
        XCTAssertEqual(makeResolver().resolve(url), .bundled(relativePath: "style.css"))
    }

    func test_bundled_rejectsTraversal() {
        let url = URL(string: "markp://app/../../etc/passwd")!
        XCTAssertNil(makeResolver().resolve(url))
    }

    func test_bundled_rejectsTraversalInMiddle() {
        let url = URL(string: "markp://app/preview/../../secrets.txt")!
        XCTAssertNil(makeResolver().resolve(url))
    }

    // MARK: - userStyle

    func test_userStyle_resolvesCSSDirectlyUnderStylesDir() {
        let url = URL(string: "markp://style/custom.css")!
        XCTAssertEqual(
            makeResolver().resolve(url),
            .userStyle(fileURL: stylesDir.appendingPathComponent("custom.css"))
        )
    }

    func test_userStyle_rejectsNonCSSExtension() {
        XCTAssertNil(makeResolver().resolve(URL(string: "markp://style/custom.txt")!))
    }

    func test_userStyle_rejectsSubdirectory() {
        XCTAssertNil(makeResolver().resolve(URL(string: "markp://style/sub/custom.css")!))
    }

    func test_userStyle_rejectsTraversalOutsideDir() {
        XCTAssertNil(makeResolver().resolve(URL(string: "markp://style/../secrets.css")!))
    }

    func test_userStyle_allowsJapaneseFileName() {
        let name = "配色.css"
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = URL(string: "markp://style/\(encoded)")!
        XCTAssertEqual(
            makeResolver().resolve(url),
            .userStyle(fileURL: stylesDir.appendingPathComponent(name))
        )
    }

    // MARK: - localImage

    func test_localImage_resolvesAbsolutePath() {
        let path = "/Users/alice/Desktop/cat.png"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "markp://file/\(encoded)")!
        XCTAssertEqual(makeResolver().resolve(url), .localImage(fileURL: URL(fileURLWithPath: path)))
    }

    func test_localImage_supportsJapaneseAndSpacesViaFullPercentEncoding() {
        let path = "/Users/alice/Desktop/猫 画像.png"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
        let url = URL(string: "markp://file/\(encoded)")!
        XCTAssertEqual(makeResolver().resolve(url), .localImage(fileURL: URL(fileURLWithPath: path)))
    }

    func test_localImage_rejectsNonImageExtension() {
        let path = "/Users/alice/Desktop/document.pdf"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "markp://file/\(encoded)")!
        XCTAssertNil(makeResolver().resolve(url))
    }

    func test_localImage_rejectsTraversal() {
        let path = "/Users/alice/../etc/passwd.png"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = URL(string: "markp://file/\(encoded)")!
        XCTAssertNil(makeResolver().resolve(url))
    }

    func test_localImage_rejectsRelativePath() {
        let url = URL(string: "markp://file/relative/path.png")!
        XCTAssertNil(makeResolver().resolve(url))
    }

    func test_localImage_acceptsAllListedExtensions() {
        let exts = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic", "avif", "ico"]
        for ext in exts {
            let path = "/Users/alice/Desktop/image.\(ext)"
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let url = URL(string: "markp://file/\(encoded)")!
            XCTAssertEqual(
                makeResolver().resolve(url),
                .localImage(fileURL: URL(fileURLWithPath: path)),
                "extension \(ext) should be accepted"
            )
        }
    }

    // MARK: - misc

    func test_unknownScheme_returnsNil() {
        XCTAssertNil(makeResolver().resolve(URL(string: "https://example.com/foo.png")!))
    }

    func test_unknownHost_returnsNil() {
        XCTAssertNil(makeResolver().resolve(URL(string: "markp://unknown/foo.png")!))
    }

    func test_mimeTypes() {
        XCTAssertEqual(AssetResolver.mimeType(forPathExtension: "png"), "image/png")
        XCTAssertEqual(AssetResolver.mimeType(forPathExtension: "SVG"), "image/svg+xml")
        XCTAssertEqual(AssetResolver.mimeType(forPathExtension: "css"), "text/css")
        XCTAssertEqual(AssetResolver.mimeType(forPathExtension: "jpg"), "image/jpeg")
        XCTAssertEqual(AssetResolver.mimeType(forPathExtension: "html"), "text/html")
        XCTAssertEqual(AssetResolver.mimeType(forPathExtension: "unknownext"), "application/octet-stream")
    }
}
