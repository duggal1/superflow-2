#!/bin/zsh
# Headless self-test for stealth-debug. Never raises a window on screen.
# Compiles the tool once, then starts two OFFSCREEN fixtures: one with a .none
# and a .readOnly window, one with no windows. Asserts the tool reports exactly
# one leaking window (exit 1) for the first and zero leaks (exit 0) for the
# second. Cleanup kills only the processes this script started.
set -u

TOOL_DIR="${0:A:h}"
TMP="$(mktemp -d -t stealth-debug-test)"
PROBE_PID=""
CLEAN_PID=""
ALLNONE_PID=""

cleanup() {
    [[ -n "$PROBE_PID" ]] && kill "$PROBE_PID" 2>/dev/null
    [[ -n "$CLEAN_PID" ]] && kill "$CLEAN_PID" 2>/dev/null
    [[ -n "$ALLNONE_PID" ]] && kill "$ALLNONE_PID" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "compiling stealth-debug tool and fixtures..."
swiftc "$TOOL_DIR/main.swift" -o "$TMP/stealth-debug" || exit 1
swiftc "$TOOL_DIR/fixtures/probe_windows.swift" -o "$TMP/probe" || exit 1

"$TMP/probe" > "$TMP/probe.out" 2>&1 &
PROBE_PID=$!
"$TMP/probe" --clean > "$TMP/clean.out" 2>&1 &
CLEAN_PID=$!
"$TMP/probe" --all-none > "$TMP/allnone.out" 2>&1 &
ALLNONE_PID=$!

for target in probe clean allnone; do
    for _ in $(seq 1 50); do
        [[ -s "$TMP/$target.out" ]] && break
        sleep 0.1
    done
done
PROBE_REPORTED="$(grep -o 'PID=[0-9]*' "$TMP/probe.out" | head -1 | cut -d= -f2)"
CLEAN_REPORTED="$(grep -o 'PID=[0-9]*' "$TMP/clean.out" | head -1 | cut -d= -f2)"
ALLNONE_REPORTED="$(grep -o 'PID=[0-9]*' "$TMP/allnone.out" | head -1 | cut -d= -f2)"
if [[ -z "$PROBE_REPORTED" || -z "$CLEAN_REPORTED" || -z "$ALLNONE_REPORTED" ]]; then
    echo "FAIL: fixtures did not report PIDs"
    exit 1
fi

"$TMP/stealth-debug" --pid "$PROBE_REPORTED" --json > "$TMP/leak.json" 2>&1
LEAK_STATUS=$?
"$TMP/stealth-debug" --pid "$PROBE_REPORTED" > "$TMP/leak.txt" 2>&1
TEXT_STATUS=$?
"$TMP/stealth-debug" --pid "$CLEAN_REPORTED" --json > "$TMP/clean.json" 2>&1
CLEAN_STATUS=$?
"$TMP/stealth-debug" --pid "$ALLNONE_REPORTED" --json > "$TMP/allnone.json" 2>&1
ALLNONE_STATUS=$?

FAIL=0
[[ "$LEAK_STATUS" -eq 1 ]] || { echo "FAIL: expected exit 1 for leak, got $LEAK_STATUS"; FAIL=1; }
[[ "$TEXT_STATUS" -eq 1 ]] || { echo "FAIL: expected exit 1 in text mode, got $TEXT_STATUS"; FAIL=1; }
[[ "$CLEAN_STATUS" -eq 0 ]] || { echo "FAIL: expected exit 0 for clean PID, got $CLEAN_STATUS"; FAIL=1; }
[[ "$ALLNONE_STATUS" -eq 0 ]] || { echo "FAIL: expected exit 0 for all-none PID, got $ALLNONE_STATUS"; FAIL=1; }

python3 - "$TMP/leak.json" "$TMP/clean.json" "$TMP/leak.txt" "$TMP/allnone.json" <<'PY' || FAIL=1
import json, sys
with open(sys.argv[1]) as f: leak = json.load(f)
assert leak["leakCount"] == 1, f"expected 1 leak, got {leak['leakCount']}"
assert leak["ok"] is False, "leak report must set ok=false"
states = sorted(w["sharingState"] for w in leak["windows"])
assert states == [0, 1], f"expected states [0,1], got {states}"
with open(sys.argv[2]) as f: clean = json.load(f)
assert clean["leakCount"] == 0, f"clean PID leaked: {clean}"
assert clean["ok"] is True, "clean PID must be ok"
text = open(sys.argv[3]).read()
assert "LEAK" in text and "capturable" in text, text
with open(sys.argv[4]) as f: allnone = json.load(f)
assert allnone["windowCount"] == 3, f"expected 3 all-none windows, got {allnone['windowCount']}"
assert allnone["leakCount"] == 0, f"all-none PID leaked: {allnone}"
assert allnone["ok"] is True, "all-none PID must be ok"
all_states = [w["sharingState"] for w in allnone["windows"]]
assert all_states == [0, 0, 0], f"expected every own window sharing state 0 (none), got {all_states}"
print("stealth-debug: leak detected (state 1), .none recognized (state 0), all-own-windows report 0, clean PID ok")
PY

if [[ "$FAIL" -eq 0 ]]; then
    echo "PASS: stealth-debug headless self-test"
    exit 0
fi
echo "FAIL: stealth-debug headless self-test"
exit 1
