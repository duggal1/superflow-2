# Island sharpness

Integrate the supplied SwiftUI design with the existing Island. Preserve the working audio/hotkey engines and unrelated shared-tree edits.

- Use one computed box for shell, wings and host hit testing; keep every live shape inside the 520 × 360 canvas.
- Draw the always-on lamp below hardware; constrain live text and history previews.
- Give history and the meeting panel keyboard focus; outside clicks dismiss history and collapse meetings, while failures keep target-app focus.
- Render notch and external states through AppKit at Retina scale. Check actual Return-to-copy behavior, geometry and all existing Island tests.
- Keep genuine notifications behind active sessions and discard stale queued notices; do not invent totals in the view model.
- Run `python3 tools/verify-island`, the normal feature test command where possible, and forbidden-pattern lint. Record unrelated failures without changing those files.

The temporary verification package symlinks the real Island and host sources and uses their production UI dependencies. It excludes unused speech-engine package dependencies; it does not substitute application data or verify the full engine integration.
