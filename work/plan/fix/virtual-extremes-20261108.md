# Virtual extreme verification + stale test fixes
## Root causes
- ModelsView: catalog grew 1→4 streaming profiles; missingCount expectation stale (1 vs 4).
- StrictCleanup: born broken — pipeline capitalizes fallback (semi-formal default) and successful stop deletes journals (keepJournals=false), so exact-raw + samples assertions can never pass.
- 6-worker GPU contention + long-transcript wall time still unmeasured on Metal.

## Changes
- ModelsViewTests: expect missingCount 4 for default-installed case.
- StrictCleanupTests: use keepJournals=true + capitalize=false to test true raw insertion; verify journals retained.
- Virtual extremes (throwaway Swift tests, not shipped): 2-vs-6 worker long-text wall time; 1/2/4/6 concurrent contention; cold load+prime+first-partial timings.

## Verify
- SessionEngine + FeatureSettings suites green.
- Probe/soak numbers recorded; no macOS UI or live-mic claims.
