import Foundation

/// Turns a file URL into one string that identifies the file, so that two URLs
/// pointing at the same file compare equal.
///
/// `URL.resolvingSymlinksInPath` is deliberately avoided: it behaves
/// inconsistently around `/private` (`/tmp/x` vs `/private/tmp/x`), which is
/// exactly the case that matters on macOS. `realpath(3)` is applied instead —
/// the same rule `FileWatcher` uses when matching FSEvents paths.
///
/// Standardization happens *first* so that `a/./b/../c` and `a/c` agree even when
/// the intermediate directories do not exist, which `realpath` alone would reject.
public enum CanonicalPath {
    public static func of(_ url: URL) -> String {
        of(url.standardizedFileURL.path)
    }

    public static func of(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(standardized, &buffer) != nil else { return standardized }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }
}
