# ADR 0001: Keep AppKit and concrete wiring in the L5 package

**Status:** Accepted

## Decision

`App/SuperflowApp` is a Swift package with a small `SuperflowApp` executable and a `SuperflowAppCore` library. The library owns adapter construction, engine wiring, window and menu controllers, and the runtime update path. Feature packages continue to depend on ports and engines only.

## Context

The app must compose the existing modules without pulling concrete adapters into L3 or L2. Keeping the composition code in a library gives the executable a minimal `@main` entry point and makes the L5 boundary visible in SwiftPM. The menu bar extra is the persistent app surface; activation policy changes to regular only while the main window is open, so the Dock icon follows that window.

## Consequences

Only the L5 package imports concrete adapters. The executable target imports `SuperflowAppCore` and declares the macOS scenes.
