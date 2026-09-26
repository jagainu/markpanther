import Foundation

/// A validated result of resolving a `markp://` URL requested by the preview
/// WKWebView, which is restricted to this custom scheme for all resource loads.
public enum ResolvedAsset: Equatable, Sendable {
    /// `markp://app/<path>` — a file bundled with the app, under its `preview/` directory.
    case bundled(relativePath: String)
    /// `markp://style/<name>.css` — a user stylesheet, directly under `stylesDirectory`.
    case userStyle(fileURL: URL)
    /// `markp://file/<percent-encoded absolute path>` — an arbitrary local image file.
    case localImage(fileURL: URL)
}

/// Resolves `markp://` URLs to on-disk locations, rejecting anything that would
/// let the preview escape its sandboxed bundled/style directories or load a
/// non-image local file.
public struct AssetResolver: Sendable {
    private let stylesDirectory: URL

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff", "heic", "avif", "ico"
    ]

    public init(stylesDirectory: URL) {
        self.stylesDirectory = stylesDirectory
    }

    public func resolve(_ url: URL) -> ResolvedAsset? {
        guard url.scheme == "markp", let host = url.host else { return nil }

        // Work from the raw string rather than `URL.path` so that a fully
        // percent-encoded absolute path (including encoded "/" as "%2F", used by
        // markp://file/...) round-trips exactly, and so a literal ".." segment
        // can't hide behind decoding quirks.
        let raw = url.absoluteString
        let prefix = "markp://\(host)/"
        guard raw.hasPrefix(prefix) else { return nil }
        let encodedRemainder = String(raw.dropFirst(prefix.count))
        guard !encodedRemainder.isEmpty,
              let decoded = encodedRemainder.removingPercentEncoding else { return nil }

        switch host {
        case "app":
            return resolveBundled(decoded)
        case "style":
            return resolveStyle(decoded)
        case "file":
            return resolveLocalImage(decoded)
        default:
            return nil
        }
    }

    private func resolveBundled(_ decoded: String) -> ResolvedAsset? {
        guard !containsTraversal(decoded) else { return nil }
        return .bundled(relativePath: decoded)
    }

    private func resolveStyle(_ decoded: String) -> ResolvedAsset? {
        // Only a bare filename directly under stylesDirectory is allowed — no
        // subdirectories, which also rules out any ".." traversal.
        guard !decoded.contains("/") else { return nil }
        guard decoded.hasSuffix(".css") else { return nil }
        let candidate = stylesDirectory.appendingPathComponent(decoded)
        return .userStyle(fileURL: candidate)
    }

    private func resolveLocalImage(_ decoded: String) -> ResolvedAsset? {
        guard decoded.hasPrefix("/") else { return nil }
        guard !containsTraversal(decoded) else { return nil }
        let ext = (decoded as NSString).pathExtension.lowercased()
        guard AssetResolver.imageExtensions.contains(ext) else { return nil }
        return .localImage(fileURL: URL(fileURLWithPath: decoded))
    }

    private func containsTraversal(_ path: String) -> Bool {
        path.split(separator: "/").contains("..")
    }

    public static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg", "svgz": return "image/svg+xml"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "heic": return "image/heic"
        case "avif": return "image/avif"
        case "ico": return "image/x-icon"
        case "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        case "md", "markdown": return "text/markdown"
        default: return "application/octet-stream"
        }
    }
}
