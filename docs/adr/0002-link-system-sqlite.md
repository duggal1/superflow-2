# ADR 0002: Link SQLite from the StorageSQLite target

**Status:** Accepted

## Decision

The `SuperflowStorageSQLite` target links the platform SQLite library with SwiftPM's `.linkedLibrary("sqlite3")` setting.

## Context

The adapter imports the system `SQLite3` module and calls its C API. Linking at the adapter target makes that native dependency explicit and keeps SQLite details out of the app and engine layers.

## Consequences

Every target that consumes `SuperflowStorageSQLite` receives the system link requirement through the package graph. No third-party SQLite wrapper is introduced.
