# Island assistant plan
## Goal
Right Option shows the assistant in the Island: open → help() streams an answer
about the latest transcript. No settings page, no Keychain prompt on press.
## Non-goals
No text field (non-activating Island can't take focus); no new LLM backend;
meeting capture unchanged.
## Invariants
Hotkey never blocks on Keychain; no transcript sent without key + explicit press;
Fn dictation untouched; no transcript stored when storage is off.
## Failure modes
No Reflection key → notice telling where to save it. No transcript → empty
prompt. Network error → failed text with Retry. Screen OCR stays opt-in.
## Approach
Reuse tested MeetingIntelligence; add Island .assistant card; bridge owns it and
feeds the buffer from the last stored transcript on open.
## Steps
1. Island: .assistant phase/event/reducer/box/view with answer + Help/Deeper/
   Retry/Cancel. Verify: FeatureIsland tests.
2. App: AppEnvironment factory (Keychain → ReflectionClient → MeetingIntelligence).
   Verify: app build.
3. Bridge + hotkey: intelligenceDown opens assistant (cancel while open).
   Verify: WarmupGesture + app tests.
4. End-to-end: rebuild, press right Option, confirm Island answer streams.
## Files
IslandLayout/Feed/Model/Root/AssistantCard; AppEnvironment; IslandBridge;
AppCoordinator+Input; IslandReducerTests; WarmupGestureTests.
