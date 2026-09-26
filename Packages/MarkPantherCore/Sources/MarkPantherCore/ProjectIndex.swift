import Foundation

/// Locates the "project root" for a given Markdown file, so the sidebar can show
/// all Markdown files that belong to the same project rather than just its own directory.
public enum ProjectRoot {
    /// How many ancestor directories to check above the file's own directory
    /// before giving up. Keeps `find(for:)` bounded even on deeply nested paths.
    private static let maxAscents = 10

    /// Finds the nearest ancestor directory (starting from `fileURL`'s own directory)
    /// that contains a `.git` entry (directory or file, to also support git worktrees).
    /// Never ascends above the user's home directory, and gives up after `maxAscents`
    /// levels. Falls back to the file's own directory when no `.git` is found.
    public static func find(for fileURL: URL) -> URL {
        let startDir = fileURL.deletingLastPathComponent()
        let homePath = resolvedPath(FileManager.default.homeDirectoryForCurrentUser.path)

        var currentDir = startDir
        var ascents = 0
        while true {
            if hasGitEntry(in: currentDir) {
                return currentDir
            }
            if resolvedPath(currentDir.path) == homePath {
                break
            }
            guard ascents < maxAscents else { break }
            let parent = currentDir.deletingLastPathComponent()
            if parent.path == currentDir.path {
                // Reached the filesystem root ("/"); nowhere further to go.
                break
            }
            currentDir = parent
            ascents += 1
        }
        return startDir
    }

    private static func hasGitEntry(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path)
    }

    /// Resolves symlinks (e.g. /tmp -> /private/tmp) via `realpath(3)` so ancestor
    /// paths can be compared reliably against the resolved home directory path.
    private static func resolvedPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil {
            return buffer.withUnsafeBufferPointer { ptr in
                String(cString: ptr.baseAddress!)
            }
        }
        return path
    }
}

/// A single Markdown file discovered by `ProjectIndex.scan`.
public struct ProjectFile: Sendable, Equatable {
    public let url: URL
    /// Path relative to the scanned root, for display in the sidebar.
    public let relativePath: String
    public let modified: Date

    public init(url: URL, relativePath: String, modified: Date) {
        self.url = url
        self.relativePath = relativePath
        self.modified = modified
    }
}

/// Recursively enumerates the Markdown files under a project root.
public struct ProjectIndex: Sendable {
    public static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    private static let excludedDirectoryNames: Set<String> = [
        "node_modules", "build", ".build", "DerivedData", "dist", "vendor", ".next", "Pods",
    ]

    /// Recursively enumerates Markdown files under `root`.
    ///
    /// - Parameters:
    ///   - root: the directory to scan.
    ///   - maxDepth: maximum recursion depth, with `root` itself at depth 0.
    ///   - maxFiles: stops (returning a partial result) once this many files are collected.
    /// - Returns: matching files sorted by `relativePath` in lexicographic order.
    public static func scan(root: URL, maxDepth: Int = 6, maxFiles: Int = 2000) -> [ProjectFile] {
        var results: [ProjectFile] = []
        let rootPath = root.standardizedFileURL.path
        scanDirectory(root, depth: 0, maxDepth: maxDepth, maxFiles: maxFiles, rootPath: rootPath, results: &results)
        results.sort { $0.relativePath < $1.relativePath }
        return results
    }

    private static func scanDirectory(
        _ directory: URL,
        depth: Int,
        maxDepth: Int,
        maxFiles: Int,
        rootPath: String,
        results: inout [ProjectFile]
    ) {
        guard depth <= maxDepth, results.count < maxFiles else { return }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            )
        } catch {
            return
        }

        for entry in entries {
            if results.count >= maxFiles { return }

            let name = entry.lastPathComponent
            // Excludes both dotfiles/dotdirectories (e.g. `.git`) and hidden Markdown files.
            if name.hasPrefix(".") { continue }

            let values = try? entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            )
            let isDirectory = values?.isDirectory ?? false
            let isSymbolicLink = values?.isSymbolicLink ?? false

            if isDirectory {
                // Never follow symlinked directories, to avoid cycles.
                if isSymbolicLink { continue }
                if excludedDirectoryNames.contains(name) { continue }
                scanDirectory(
                    entry, depth: depth + 1, maxDepth: maxDepth, maxFiles: maxFiles,
                    rootPath: rootPath, results: &results
                )
            } else {
                let ext = entry.pathExtension.lowercased()
                guard markdownExtensions.contains(ext) else { continue }
                let modified = values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
                results.append(
                    ProjectFile(
                        url: entry,
                        relativePath: relativePath(of: entry, rootPath: rootPath),
                        modified: modified
                    )
                )
            }
        }
    }

    private static func relativePath(of url: URL, rootPath: String) -> String {
        let fullPath = url.standardizedFileURL.path
        guard fullPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        var relative = String(fullPath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }
}
