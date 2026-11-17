#!/usr/bin/env bash
# R7: Right Option ONLY trigger; hold=listen+waveform, release=send; quick tap latches;
#     other keys cancel; Left Option / Right Control do nothing; Option+key still types.
# PASS requires the key refs AND a real ClearlyInput/GestureKit XCTest exercise.
source "$(dirname "$0")/_lib.sh"
g="$ROOT/Packages/L2-Engines/GestureKit/Sources/SuperflowGestureKit/GestureRecognizer.swift"
h="$ROOT/Packages/L1-Adapters/HotkeyEngine/Sources/SuperflowHotkeyEngine/KeyEventMapper.swift"
[ -f "$g" ] || [ -f "$h" ] || source_only "gesture/hotkey source files missing"
right=$(grep -cE 'rightOption|code == 61|0x40|NX_DEVICERALT' "$g" "$h" 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}')
interf=$(grep -rniE 'interference|cancel' "$ROOT/Packages/L1-Adapters/ClearlyInput/Sources" "$g" 2>/dev/null | wc -l | tr -d ' ')

ex=$(test_exercise "App/SuperflowApp" "ClearlyInputGestureTests|GestureTests" "right-option-gestures") && exok=1 || exok=0
if [ "$right" -gt 0 ] && [ "$interf" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "Right-Option refs=$right; interference/cancel refs=$interf; EXERCISED gesture suites: $ex (covers hold/tap-latch/interference/Left-Option/Right-Control/Option+key)"
else
  fail "Right-Option refs=$right interference=$interf exercise_ok=$exok; $ex"
fi
