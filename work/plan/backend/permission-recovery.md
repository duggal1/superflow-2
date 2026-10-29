# Permission recovery

Fix the missing Input Monitoring entry and stale grants without changing TCC data or granting access silently.

Evidence: packaged app used an ad-hoc designated requirement tied to its binary hash. A valid Superflow Development identity exists. Accessibility incorrectly fell back to a listen-only Input Monitoring tap. The sidebar previously opened Settings without requesting access.

Second pass, from live tccd logs on macOS 27.2:

- Every `kTCCServiceListenEvent` request from `com.superflow.app` was `preflight=yes`, so the app never asked TCC to write a row. The repair path short-circuited because `CGEvent.tapCreate` reported a tap, which is not proof of a grant.
- `tccd` logged `Failed to match existing code requirement for subject com.superflow.app` for ListenEvent, Accessibility and Microphone: rows from earlier ad-hoc builds are stale.
- A probe bundle signed with the same development certificate produced a `Modify` event for `kTCCServiceListenEvent` after calling `CGRequestListenEventAccess()` + `IOHIDRequestAccess()`, proving that request registers the row and the signing identity is valid.
- `tccutil reset ListenEvent|Accessibility|Microphone com.superflow.app` succeeds without root.

Changes: status for Input Monitoring now trusts only `CGPreflightListenEventAccess()` and `IOHIDCheckAccess()`. Request calls both `CGRequestListenEventAccess()` and `IOHIDRequestAccess()`. Prefer the existing development certificate unless explicitly overridden; keep the same identity across local builds. Separate Accessibility trust from Input Monitoring. Request access before navigating, reveal the exact running bundle if still denied, and refresh subscriptions on app/workspace activation. Preserve user approval and existing data.

Verification: 16 PermissionsKit tests passed, including the regression that a listen tap is not a grant. Packaging smoke tests passed. Stale TCC rows for this machine were reset. A probe bundle signed with the Superflow Development certificate registered a ListenEvent row; the same request from the real app still needs one user approval, which cannot be performed here.
