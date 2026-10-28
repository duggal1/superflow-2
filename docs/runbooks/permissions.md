# macOS permissions

Superflow checks permissions through the framework that enforces each grant. A saved preference is not proof that an event tap, microphone stream, or system-audio stream works.

| Capability | Permission | Verification path |
|---|---|---|
| Dictation audio | Microphone | Start the onboarding practice capture and confirm audio arrives. |
| Fn/Right Command detection | Input Monitoring | Start the event tap and exercise the gesture on the physical keyboard. |
| Synthetic paste and active key tap | Accessibility | Dictate into a sandbox field and verify the original frontmost app receives the text. |
| Meeting remote audio | Screen & System Audio Recording | Start a meeting capture and verify system-source samples arrive. |

Use onboarding or Settings to request a grant or open its System Settings pane. After changing a grant, return to Superflow; its permission stream re-probes status when the app becomes active. If an event tap was revoked, the app stops its hotkey listener and displays a status message. The menu bar controls remain available for manual start and stop.

System audio is requested only when meeting capture starts. A meeting can continue with microphone audio if system capture fails; the session should show a gap notice.

For release acceptance, test both first-time requests and revocation while the app is running. Confirm the event tap actually installs and that microphone/system audio streams produce samples.

## Input Monitoring does not list Superflow

This is the most common failure, and it has two causes.

**1. The app was never registered with TCC.** `CGRequestListenEventAccess()` only raises a prompt the first time TCC sees a given code identity. When a stale record already exists it returns `false`, does nothing, and the bundle never appears in the Input Monitoring list — even though Accessibility lists it. The gate therefore requests *and then exercises* a listen-only event tap (`CGEvent.tapCreate`), which is what makes TCC record the app. If the entry still does not appear, call `revealAppForManualGrant()` (or find `dist/Superflow.app` yourself) and drag it onto the `+` button in that pane.

**2. The code identity changed.** TCC keys every grant to the signature. An ad-hoc signed build (`make app` with the default `-`) has a different cdhash on every rebuild, so each rebuild is a new app and old grants are orphaned. Fix it once:

```bash
./tools/dev-signing                                  # creates a stable local identity
export SUPERFLOW_SIGN_IDENTITY="Superflow Development"
make app
```

Grant permissions once after that and they survive rebuilds. For distribution, use Developer ID (ADR 0012) so end users never see this.

**Why the two panes disagree.** Accessibility and Input Monitoring are separate TCC services (`kTCCServiceAccessibility` vs `kTCCServiceListenEvent`). A grant in one says nothing about the other, and an app can legitimately appear in only one of them until the corresponding API call is made.

## Accessibility looks granted but insertion still fails

A stale TCC record survives a rebuild with a different code identity. System
Settings can show the Superflow switch on while `AXIsProcessTrusted()` returns
false for the running build, so every dictation falls back to the clipboard and
the Island shows its copy card. Fix it by removing the stale entry and granting
again:

```bash
tccutil reset Accessibility com.superflow.app   # if the app is installed as a bundle
./tools/dev-signing
export SUPERFLOW_SIGN_IDENTITY="Superflow Development"
make app
```

Then remove the old Superflow row in System Settings > Privacy & Security >
Accessibility, add the freshly built `dist/Superflow.app`, and relaunch. A
rebuild that changes the ad-hoc signature has the same effect, so use the stable
development identity above.

Insertion also needs Accessibility for the *verification* step and the
Accessibility fallback. With the grant missing, the transcript is written to the
clipboard (marked transient) and the Island offers Copy; it is not silently
dropped.

## Terminal and password fields

macOS Secure Input (`IsSecureEventInputEnabled()`) swallows synthetic Cmd+V even
with Accessibility granted. Superflow skips the chord and tries Accessibility
selected-text insertion. A focused secure field is never written at all: the
text stays off the clipboard and is offered through the Island copy card. If a
terminal still refuses both paths, use the card to paste manually.

