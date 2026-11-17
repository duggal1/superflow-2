#!/usr/bin/env bash
# R18: all testing headless; native apps via open -g -j; no global keys/cursor;
#      drivers in tools/, JSON out, documented in tools/validate-headless/README.md.
# PASS requires the harness artefacts AND a real driver invocation that proves no focus steal.
source "$(dirname "$0")/_lib.sh"
d="$ROOT/tools/validate-headless"
readme=$([ -f "$d/README.md" ] && echo yes || echo no)
driver=$([ -f "$d/validate-headless" ] && echo yes || echo no)
uibin=$(find "$d" -name 'Island*Driver.swift' -o -name '*Probe.swift' 2>/dev/null | wc -l | tr -d ' ')
bad=$(grep -rnE '(^|[^#])\bopen -a\b|\bopen "[^"]*\.app"|\bkeycode\b|\bcliclick\b|CGEventPost\(kCGHIDEventTap|osascript.*keystroke' "$d" 2>/dev/null | grep -vE 'open -g -j|never|Never|NEVER|forbidden|banned' | wc -l | tr -d ' ')

# Real exercise: run the compiled frontmost probe; it must return JSON and the
# frontmost app must NOT be Superflow (proof no GUI focus steal happened).
front=$(timeout 30 "$d/IslandUIDriver" frontmost 2>&1)
frc=$?
ff=$(printf '%s' "$front" | grep -oE '"bundle"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1)
steal=$(printf '%s' "$front" | grep -q 'com.superflow.app' && echo yes || echo no)
if [ "$readme" = yes ] && [ "$driver" = yes ] && [ "$uibin" -gt 0 ] && [ "$bad" -eq 0 ] && [ "$frc" -eq 0 ] && [ "$steal" = no ]; then
  pass "harness=$driver README=$readme Swift drivers=$uibin forbidden GUI/global-key patterns=$bad; EXERCISED IslandUIDriver frontmost rc=$frc ($ff, superflow_steal=$steal) — JSON out, no focus steal"
else
  fail "harness=$driver README=$readme drivers=$uibin forbidden=$bad driver_rc=$frc frontmost='$front' superflow_steal=$steal"
fi
