import Foundation

/// The only filesystem scope a text stage may reason about.
///
/// The root is injected by the composition root, never discovered by a text
/// stage. `paths` is a small, bounded, project-relative index that is built on
/// explicit project open/refresh. A path that is not relative, contains `..`,
/// or would escape the root is dropped at construction time.
public struct ProjectContext: Sendable, Equatable {
    /// Soft bound from the plan: a few thousand entries, never a whole disk.
    public static let pathLimit = 4_096
    public static let pathLengthLimit = 512

    public var root: URL?
    /// Project-relative paths, directories included, in stable index order.
    public var paths: [String]
    /// True when the active session is a coding/agent session.
    public var isCoding: Bool
    /// True when the session explicitly selected this project instead of the
    /// pipeline guessing from the frontmost application.
    public var approvedByUser: Bool

    public init(root: URL? = nil, paths: [String] = [], isCoding: Bool = false,
                approvedByUser: Bool = false) {
        self.root = Self.approvedRoot(root)
        self.paths = Self.boundedPaths(paths)
        self.isCoding = isCoding
        self.approvedByUser = approvedByUser
    }

    public static let none = ProjectContext()

    /// Path resolution is only available with an approved root and an index.
    public var resolvesPaths: Bool { root != nil && !paths.isEmpty }

    /// Lexical containment check. No filesystem access at cleanup time.
    public func contains(relative path: String) -> Bool {
        guard let root, let normalized = Self.normalizedRelative(path) else { return false }
        let rootPath = root.standardizedFileURL.path
        let candidate = root.appendingPathComponent(normalized).standardizedFileURL.path
        return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
    }

    /// Returns the normalized relative form when it is safe to use.
    public func normalized(relative path: String) -> String? {
        guard let normalized = Self.normalizedRelative(path),
              contains(relative: normalized) else { return nil }
        return normalized
    }

    /// Rejects absolute paths, `..`, NUL and empty components. Preserves a
    /// trailing slash so directory results stay unambiguous.
    public static func normalizedRelative(_ path: String) -> String? {
        var value = path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\0") else { return nil }
        let isDirectory = value.hasSuffix("/")
        var components: [String] = []
        for part in value.split(separator: "/", omittingEmptySubsequences: true) {
            let component = String(part)
            if component == "." { continue }
            guard component != "..", component.count <= 255 else { return nil }
            components.append(component)
        }
        guard !components.isEmpty else { return nil }
        value = components.joined(separator: "/")
        guard value.utf8.count <= pathLengthLimit else { return nil }
        return isDirectory ? value + "/" : value
    }

    private static func approvedRoot(_ root: URL?) -> URL? {
        guard let root, root.isFileURL else { return nil }
        let path = root.path
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let resolved = root.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path != "/" else { return nil }
        return resolved
    }

    private static func boundedPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        out.reserveCapacity(min(paths.count, pathLimit))
        for raw in paths {
            guard out.count < pathLimit else { break }
            guard let normalized = normalizedRelative(raw) else { continue }
            guard seen.insert(normalized).inserted else { continue }
            out.append(normalized)
        }
        return out
    }
}
