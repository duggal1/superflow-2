# Permission recovery

Fix the missing Input Monitoring entry and stale grants without changing TCC data or granting access silently.

Evidence: packaged app used an ad-hoc designated requirement tied to its binary hash. A valid Superflow Development identity exists. Accessibility incorrectly fell back to a listen-only Input Monitoring tap. The sidebar previously opened Settings without requesting access.

Changes: prefer the existing development certificate unless explicitly overridden; keep the same identity across local builds. Separate Accessibility trust from Input Monitoring. Request access before navigating, reveal the exact running bundle if still denied, and refresh subscriptions on app/workspace activation. Preserve user approval and existing data.

Verification: 15 PermissionsKit tests passed; packaging smoke tests passed; full current-tree app and helper build passed. Confirm packaged/build UUIDs match, signature uses certificate-based identity rather than cdhash, and launched process uses dist/Superflow.app. macOS Settings exposed no windows to automation; final toggle approval cannot be verified or performed here. If the row is absent, the user must add the revealed bundle using +.
