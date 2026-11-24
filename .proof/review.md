# Independent Review — delete / rebuild / sign / install / open Superflow

Read-only review. Re-ran every check headless against the REAL installed artifact at
`/Applications/Superflow.app`. No GUI opened; no app launched or quit; no source, build output,
or artifact modified; nothing deleted.

## Verdicts

1. **Old binary deleted before rebuild — PASS.**
   `grep -n "Step 2" .proof/progress.md` → `29:- Step 2 DONE: deleted /Applications/Superflow.app and stale dist/Superflow.app; both absent afterwards.`
   Current state: `ls -ld /Applications/Superflow.app` → `drwxr-xr-x@ ... Nov 24 22:36 /Applications/Superflow.app` (NEW, signature dated `Nov 24, 2026 at 22:37:00`); `find dist -maxdepth 1 -name Superflow.app -print` → no output. Deletion is log-asserted (no raw `rm` transcript in `.proof`), consistent with replaced artifact and empty dist.

2. **Signing identity exists and signed the installed build — PASS.**
   `security find-identity -v -p codesigning` → `1) 9CCF4387668230D268000A2F08EBA9ECF47DA6EC "Superflow Development"` / `1 valid identities found`.
   `codesign -dvv /Applications/Superflow.app | grep Authority` → `Authority=Superflow Development` (helper, 3 libaudiocpp dylibs and llama.framework carry the same authority).

3. **Rebuild was a real release build from current source — PASS.**
   `.proof/progress.md:30` → `SUPERFLOW_SIGN_IDENTITY="Superflow Development" make app exit 0, 264s app + 27s helper release builds`; `.proof/build.log` → `Build complete! (264.24 sec)` (app), `Build complete! (27.20 sec)` (helper), `Building for production...`, and packaging lines `Built .../dist/Superflow.app` / `helper: .../Release/SuperflowInferenceHelper` / `identity: Superflow Development`. `grep -n CONFIGURATION Makefile` → `CONFIGURATION=release SUPERFLOW_BIN_DIR="$$bin_dir" tools/package-app --skip-build` plus two `swift build ... --configuration release`. `git status --short --branch` → no source edits.

4. **Installed app verifies headlessly — PASS.**
   `codesign --verify --deep --strict /Applications/Superflow.app` → `EXIT=0`.
   `codesign -dvv /Applications/Superflow.app` → `Authority=Superflow Development`, `Signed Time=Nov 24, 2026 at 22:37:00`, `Identifier=com.superflow.app`.
   `codesign -d --entitlements :- /Applications/Superflow.app` → `<key>com.apple.security.device.audio-input</key><true/>`.
   `plutil -lint /Applications/Superflow.app/Contents/Info.plist` → `OK`; `CFBundleExecutable=SuperflowApp`; `CFBundleIdentifier=com.superflow.app`.
   `file /Applications/Superflow.app/Contents/MacOS/SuperflowApp` → `Mach-O 64-bit executable arm64`.
   Nested present + verified: `find .../Frameworks` → 3 libaudiocpp dylibs; `find .../XPCServices` → `SuperflowInferenceHelper.xpc`; `codesign --verify --strict` on each dylib + xpc + nested llama.framework → all `PASS`; 9 `*.bundle` resource bundles present in Contents/Resources.

5. **Installed at /Applications, moved not copied — PASS.**
   `grep -n "Step 5" .proof/progress.md` → `35:- Step 5 DONE: mv dist/Superflow.app /Applications/Superflow.app`.
   `find dist -maxdepth 1 -name Superflow.app -print` → no output (no bundle left in dist; `ls -ld dist` → `drwxr-xr-x@ ... Nov 24 22:37 dist`).

6. **App running (not launched/quit by this review) — PASS.**
   `pgrep -fl SuperflowApp` → `3098 /Applications/Superflow.app/Contents/MacOS/SuperflowApp` (path is the installed app).

7. **No scope violations outside authorized binary deletion — PASS, with flags.**
   `git status --short --branch` → `## main...origin/main`, ` M .proof/progress.md`, ` M .proof/requirements.md`, ` D .proof/{extreme-after,extreme-debug,quality-after,quality-current}.txt`, `?? .proof/archive/20261124T170052Z/`. All changes are under `.proof/` evidence state; no source edits, no new secrets, no destructive action outside the explicitly authorized `/Applications/Superflow.app` + `dist/Superflow.app` deletion. `ls .proof/archive/20261124T170052Z/` → the four "deleted" `.txt` files are present there, i.e. archived per `rules.yaml` new_task rule, not destroyed.

## Flags / partials / unverified

- Requirement 1 deletion and requirement 5 `mv` rest on progress-log assertions (`progress.md:29`, `progress.md:35`); no raw command transcript exists in `.proof`, and current state alone cannot distinguish `mv` from copy-then-delete. Both are consistent with all independently observed state (fresh installed bundle, empty dist, new signature timestamp). Log-asserted, not re-observable after the fact.
- `.proof/progress.md` and `.proof/requirements.md` are modified and old `.proof` files were archived into `.proof/archive/20261124T170052Z/`; this follows `rules.yaml new_task` state handling and is not a source change. Flagged for transparency, not a failure.
- The only "delete" action evidenced is the user-authorized removal of the old app bundles; the `.proof` `.txt` removals are moves into the archive, with content intact.
- `tools/dev-signing` contains a pre-existing hard-coded local PKCS#12 password (`superflow`) used only to generate a login-keychain identity; no secret was introduced or committed by this task.

## Outcome

7/7 PASS (2 log-asserted items flagged above). Nothing opened, launched, quit, or edited outside `.proof/review.md`.
