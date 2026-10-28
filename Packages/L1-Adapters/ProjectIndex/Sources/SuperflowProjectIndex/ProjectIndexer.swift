import Darwin
import Foundation
import SuperflowKernel

/// Bounded, explicit project indexer.
///
/// This is the only place that walks a project tree. It runs when the user opens
/// or refreshes a project, never during cleanup, and returns a `ProjectContext`
/// whose paths are project-relative and capped by the kernel. Symlinks are not
/// followed, hidden files are skipped, and heavy generated directories are
/// pruned so the index stays small and local.
public struct ProjectIndexer: Sendable {
    /// Directories that never belong in a spoken-path index.
    public static let skippedDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "Pods", "DerivedData",
        "SourcePackages", "venv", "__pycache__", ".venv", "target",
    ]

    public init() {}

    /// Returns nil when the root is not an existing directory. The caller must
    /// have selected this root explicitly; nothing is discovered here.
    public func build(root: URL, isCoding: Bool, approvedByUser: Bool = true,
                      limit: Int = ProjectContext.pathLimit,
                      maxDepth: Int = 10) -> ProjectContext? {
        let fileManager = FileManager.default
        // The enumerator canonicalizes `/var` to `/private/var`; use the same
        // canonical path for the root so prefix containment cannot silently
        // drop every entry.
        let resolved = Self.canonicalURL(root)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: resolved,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return nil }

        let rootPath = resolved.path.hasSuffix("/") ? resolved.path : resolved.path + "/"
        let cap = max(1, min(limit, ProjectContext.pathLimit))
        var paths: [String] = []

        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            let isDirectory = values?.isDirectory == true
            guard url.path.hasPrefix(rootPath) else { continue }
            let relative = String(url.path.dropFirst(rootPath.count))
            guard let normalized = ProjectContext.normalizedRelative(relative) else { continue }

            if isDirectory {
                if Self.skippedDirectories.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                paths.append(normalized + "/")
                if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            } else {
                paths.append(normalized)
            }
            if paths.count >= cap { break }
        }

        paths.sort()
        return ProjectContext(root: resolved, paths: paths, isCoding: isCoding,
                              approvedByUser: approvedByUser)
    }

    private static func canonicalURL(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else {
            return url.resolvingSymlinksInPath().standardizedFileURL
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }
}
