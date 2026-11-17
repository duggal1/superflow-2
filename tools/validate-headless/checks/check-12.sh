#!/usr/bin/env bash
# R12: screen reading default ON; capture per send (Island excluded); Vision OCR fallback;
#      inline permission state + Settings link; answers continue without screen context.
# PASS requires the default-on source AND a real XCTest exercise of the default.
source "$(dirname "$0")/_lib.sh"
mi="$ROOT/Packages/L2-Engines/MeetingIntelligence/Sources/SuperflowMeetingIntelligence"
sr="$mi/ScreenReader.swift"
[ -f "$sr" ] || source_only "ScreenReader.swift missing"
default=$(grep -nE 'screenAware' "$mi/MeetingIntelligence.swift" 2>/dev/null | grep -E 'true|= true' | wc -l | tr -d ' ')
exclude=$(grep -rnE 'excludingWindows|excluding|SCContentFilter\(display' "$sr" "$ROOT/App/SuperflowApp/Sources" 2>/dev/null | wc -l | tr -d ' ')
vision=$(grep -cE 'Vision|VNRecognizeText|OCR|recognizedText' "$sr" 2>/dev/null | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "HeadlessIntelligencePromptTests|MeetingIntelligenceTests" "screen-default") && exok=1 || exok=0
if [ "$default" -gt 0 ] && [ "$exclude" -gt 0 ] && [ "$vision" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "screenAware default-true refs=$default; SCK exclusion=$exclude; Vision/OCR=$vision; EXERCISED screen-context-defaults-on: $ex"
else
  fail "screenAware-default=$default exclusion=$exclude OCR=$vision exercise_ok=$exok; $ex"
fi
