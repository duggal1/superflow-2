# ADR 0018: Spike I — meeting detection, calendar seeding and voice memory

Status: Accepted; runtime and quality evidence pending

## Context

Addendum A §28.6–§28.7 requires a `MeetingDetector` port and an optional
read-only `CalendarProvider`, plus opt-in voice memory if FluidAudio exposes
usable speaker embeddings. This spike verifies the OS and library surfaces
before any adapter is written.

Environment checked: macOS 27.2, `MacOSX27.0.sdk`, FluidAudio 0.17.7 (pinned by
`Package.resolved`).

## Verified facts

### Core Audio process properties

`AudioHardware.h` (Process Properties) defines:

- `kAudioProcessPropertyPID = 'ppid'`
- `kAudioProcessPropertyBundleID = 'pbid'`
- `kAudioProcessPropertyDevices = 'pdv#'`
- `kAudioProcessPropertyIsRunning = 'pir?'`
- `kAudioProcessPropertyIsRunningInput = 'piri'`
- `kAudioProcessPropertyIsRunningOutput = 'piro'`

The hardware object exposes `kAudioHardwarePropertyProcessObjectList = 'prs#'`
and `kAudioHardwarePropertyTranslatePIDToProcessObject = 'id2p'`. A process
object sits in `kAudioProcessClassID = 'clnt'`.

`CATapDescription.h` provides include and exclude initializers:
`initStereoMixdownOfProcesses:`, `initStereoGlobalTapButExcludeProcesses:`,
mono variants, and device-UID/stream variants. The existing
`CoreAudioTapCapture` already uses
`stereoGlobalTapButExcludeProcesses` with the app's own PID, which matches the
addendum's default tap scope.

Conclusion: per-process "is running input" is a real API, not a guess. It is a
usable detection signal. Per-app tap scope is expressible with the same API.

### EventKit

`EKEventStore.h` declares `requestFullAccessToEventsWithCompletion:` and
`requestWriteOnlyAccessToEventsWithCompletion:`, available on macOS 14.0+.
The app will request full access and only read. The required usage-description
key `NSCalendarsFullAccessUsageDescription` is present in the installed Xcode
build specification. Calendar access is a separate privacy grant from
microphone and Accessibility.

### Window titles

`AXAttributeConstants.h` declares `kAXTitleAttribute` and
`kAXFocusedWindowAttribute`. `CGWindow.h` declares `kCGWindowName` and
`CGWindowListCopyWindowInfo`. Accessibility is the preferred path because the
product already needs that grant; Core Graphics window names may additionally
require Screen Recording, which the product does not otherwise request.

### Speaker embeddings

FluidAudio 0.17.7 contains `SpeakerManager`, `SpeakerUtilities` (cosine
distance, embedding validation, closest-speaker lookup, merge/update) and
`EmbeddingExtractor`. So the ingredients for a local voiceprint exist.

The current `FluidAudioDiarizer` uses Sortformer `fastV2_1` with four fixed
slots and converts only finalized segments to `remote-N` labels. It does not
surface embeddings. Voice memory therefore needs a new extraction path, not a
flag flip.

## Decision

1. `MeetingDetection` is an L1 adapter behind `MeetingDetector`. Signals:
   known conferencing bundle IDs, browser window titles, the per-process
   `IsRunningInput` property, and active system output. Signals are debounced
   and scored. It emits a suggestion only.
2. Detection never auto-starts. A per-app opt-in may allow automatic start
   later; the default is suggestion + explicit keypress. `Don't ask for this
   app` is persisted per bundle ID.
3. `CalendarEventKit` is an L1 adapter behind `CalendarProvider`. Read-only.
   It asks for full access once, matches events by time overlap, and supplies a
   title and attendee names. Attendee names go to the Learning Inbox as
   suggestions, never straight into the dictionary.
4. Window-title access uses Accessibility first. Core Graphics is a fallback
   only if it works with the grants already held; if it needs Screen Recording,
   drop it rather than widen permissions for a weak signal.
5. Voice memory stays **off** and unwritten. Before any code, the spike must
   show: stable embeddings for the same speaker across meetings, a threshold
   with acceptable false-name rate, a delete-all path, and no embedding ever
   leaving the device. Until then the UI offers manual rename only.
6. Identity is the stable `speakerId`. Renaming applies to every turn through
   that id; display names are mutable metadata.

## Alternatives considered

1. Detect meetings by polling window titles only. Rejected: browser titles are
   inconsistent and Accessibility reads can be slow; audio activity is the
   stronger signal.
2. Use `DeviceIsRunningSomewhere` instead of the process property. Rejected: it
   cannot tell which process is using the input.
3. Ship voice memory behind the existing Sortformer adapter. Rejected: the
   adapter exposes no embeddings and the model quality is unmeasured.

## Consequences and limits

- Detection adds a process-list poll; it must be cheap, off the main actor and
  paused while a meeting is already recording.
- Calendar permission can be denied; the app must work with no calendar.
- An attendee list is not a speaker mapping. It is only a name suggestion.

## Unverified / next evidence

- [ ] Real `IsRunningInput` values while Zoom, Meet, Teams and Slack huddles are
      in a call, and while the app itself records.
- [ ] Mid-meeting app launch: the process list changes and the tap must follow.
- [ ] Per-app include/exclude tap behaviour and its permission prompt.
- [ ] Whether browser window titles are exposed with Accessibility only.
- [ ] EventKit prompt, read latency and attendee shape on current macOS.
- [ ] Embedding stability, threshold and Sortformer/embedding compatibility.
- [ ] Full four-source matrix on device.

## Evidence

- `MacOSX27.0.sdk/.../CoreAudio.framework/Headers/AudioHardware.h` lines 586,
  633–634, 1962–1977
- `.../CoreAudio.framework/Headers/CATapDescription.h` lines 56–111
- `.../EventKit.framework/Headers/EKEventStore.h` lines 84–86
- `.../HIServices.framework/Headers/AXAttributeConstants.h` lines 48, 115
- `.../CoreGraphics.framework/Headers/CGWindow.h` lines 118, 170
- `Packages/L1-Adapters/SystemAudioCapture/Sources/.../CoreAudioTapCapture.swift`
- `Packages/L1-Adapters/DiarizationFluidAudio/Sources/.../SpeakerDiarizer.swift`
- FluidAudio 0.17.7 `Diarizer/Clustering/SpeakerManager.swift`,
  `Diarizer/Clustering/SpeakerOperations.swift`,
  `Diarizer/Extraction/EmbeddingExtractor.swift`
- Addendum A §28.6–§28.7
