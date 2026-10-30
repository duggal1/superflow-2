import SuperflowStorageSQLite

/// What the window says when the library cannot open. A full volume is the one
/// failure with a user action that does not risk their data, so it gets its own
/// wording instead of SQLite's error text.
func startupMessage(for error: Error) -> String {
    if let storage = error as? SQLiteError, storage.isDiskFull {
        return """
        Superflow needs free disk space before it can open your library. \
        Free some space, then choose Try again. Your existing transcripts are untouched.
        """
    }
    return "Superflow could not open its local database. \(error.localizedDescription)"
}
