public enum CleanPriority: Sendable {
    case interactive, background
    @TaskLocal public static var current: CleanPriority = .background
}

/// The cleaner starts its deadline after acquiring an inference session.
public protocol DeadlineManagedTextCleaner: TextCleaner {}
