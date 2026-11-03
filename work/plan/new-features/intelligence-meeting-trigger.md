# Intelligence meeting trigger
Root cause: the configured modifier opens settings instead of starting meeting capture.
Changes: give Intelligence a distinct sparkles icon in navigation and the palette; route its trigger to Meetings and existing capture/Island handling; guard duplicate starts.
Files: Glyph.swift, MainWindowController.swift, AppCommandPalette.swift, AppCoordinator.swift, AppCoordinator+Input.swift, WarmupGestureTests.swift.
Verify: focused shortcut mapper and coordinator tests. Physical keyboard and live capture require manual confirmation.
