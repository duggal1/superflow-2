#!/usr/bin/env bash
# Explicit test-integrity + real-exercise gate (backs R20; runnable standalone).
#
# Strengthening over the old harness: this is the check that makes a green
# verdict require REAL execution, not source grep. It verifies, against git HEAD:
#   * the two frozen Island tests are restored BYTE-FOR-BYTE (no weakening);
#   * no test file was deleted and no test lost assertions or test funcs;
#   * lint (tools/lint-forbidden) is clean;
#   * the app compiles in release;
#   * the six focused packages pass their real XCTest suites.
#
# One verdict line: <PASS|FAIL>\t<evidence>. Raw logs in $PROOF/logs/.
source "$(dirname "$0")/_lib.sh"
mkdir -p "$PROOF/logs"

# ---- 1. Frozen tests restored, byte-identical to HEAD --------------------
f1="Packages/L3-Features/FeatureIsland/Tests/FeatureIslandTests/IdleLampMotionTests.swift"
f2="Packages/L3-Features/FeatureIsland/Tests/FeatureIslandTests/IslandSnapshotTests.swift"
frozen=""; frozen_ok=1
for f in "$f1" "$f2"; do
  if [ ! -f "$ROOT/$f" ]; then
    frozen+="$(basename "$f")=MISSING; "; frozen_ok=0; continue
  fi
  if diff -q <(git -C "$ROOT" show "HEAD:$f" 2>/dev/null) "$ROOT/$f" >/dev/null 2>&1; then
    frozen+="$(basename "$f")=byte-identical-to-HEAD; "
  else
    frozen+="$(basename "$f")=DIFFERS-FROM-HEAD; "; frozen_ok=0
  fi
done
# The specific frozen assertions must still be present.
gutter="testLongCancelledTranscriptKeepsUndoInsideTheContentGutter"
if grep -qF "$gutter" "$ROOT/$f2" 2>/dev/null && \
   grep -qF 'XCTAssertLessThanOrEqual(right,' "$ROOT/$f2" 2>/dev/null && \
   grep -qF 'XCTAssertGreaterThan(right - left' "$ROOT/$f2" 2>/dev/null; then
  frozen+="gutter-assertions=present; "
else
  frozen+="gutter-assertions=MISSING; "; frozen_ok=0
fi

# ---- 2. No test file deleted vs HEAD -------------------------------------
deleted=$(git -C "$ROOT" diff HEAD --name-only --diff-filter=D 2>/dev/null | grep -E '(^|/)Tests?/|Tests\.swift$' | wc -l | tr -d ' ')

# ---- 3. No test weakened vs HEAD (fewer test funcs or XCTAsserts) --------
weakened=""; weak=0
while IFS= read -r tf; do
  [ -z "$tf" ] && continue
  [ -f "$ROOT/$tf" ] || continue   # deletions already counted above
  hf=$(git -C "$ROOT" show "HEAD:$tf" 2>/dev/null | grep -cE 'func test' || true)
  wf=$(grep -cE 'func test' "$ROOT/$tf" 2>/dev/null || true)
  ha=$(git -C "$ROOT" show "HEAD:$tf" 2>/dev/null | grep -c 'XCTAssert' || true)
  wa=$(grep -c 'XCTAssert' "$ROOT/$tf" 2>/dev/null || true)
  hf=${hf:-0}; wf=${wf:-0}; ha=${ha:-0}; wa=${wa:-0}
  if [ "$wf" -lt "$hf" ] || [ "$wa" -lt "$ha" ]; then
    weakened+="$(basename "$tf")[funcs:${hf}->${wf},asserts:${ha}->${wa}]; "; weak=$((weak+1))
  fi
done < <(git -C "$ROOT" ls-tree -r --name-only HEAD 2>/dev/null | grep -E '(^|/)Tests?/.*\.swift$|Tests\.swift$')

# ---- 4. Lint clean -------------------------------------------------------
timeout 200 tools/lint-forbidden >"$PROOF/logs/lint.log" 2>&1
lr=$?
lv=$(grep -cE 'violation|Forbidden|exceeds 400' "$PROOF/logs/lint.log" 2>/dev/null | tr -d ' ')

# ---- 5. Release build ----------------------------------------------------
timeout 280 swift build --package-path "$ROOT/App/SuperflowApp" --configuration release \
  >"$PROOF/logs/build-app-release.log" 2>&1
br=$?
berr=$(grep -cE 'error:' "$PROOF/logs/build-app-release.log" 2>/dev/null | tr -d ' ')

# ---- 6. Focused packages: real XCTest suites -----------------------------
pkgs=(
  "Packages/L3-Features/FeatureIsland"
  "Packages/L2-Engines/GestureKit"
  "Packages/L2-Engines/MeetingIntelligence"
  "Packages/L1-Adapters/ClearlyInput"
  "Packages/L1-Adapters/ClearlyStealth"
  "Packages/L3-Features/FeatureIntelligence"
)
tr=0; tests=""
for p in "${pkgs[@]}"; do
  [ -d "$ROOT/$p" ] || { tests+="$(basename "$p")=absent; "; tr=1; continue; }
  timeout 280 swift test --package-path "$ROOT/$p" >"$PROOF/logs/test-$(basename "$p").log" 2>&1
  rc=$?; n=$(grep -Eo 'Executed [0-9]+ test' "$PROOF/logs/test-$(basename "$p").log" | grep -Eo '[0-9]+' | tail -1)
  n=${n:-0}; tests+="$(basename "$p")=$rc/${n}t; "; [ "$rc" -ne 0 ] && tr=1
done

# ---- Verdict -------------------------------------------------------------
ev="frozen[$frozen]; frozen_ok=$frozen_ok; deleted_test_files=$deleted; weakened_test_files=$weak {${weakened:-none}}; lint=$lr($lv findings); build_release=$br(errors=$berr); swift_test{$tests}"
if [ "$frozen_ok" -eq 1 ] && [ "$deleted" -eq 0 ] && [ "$weak" -eq 0 ] && \
   [ "$lr" -eq 0 ] && [ "$br" -eq 0 ] && [ "$tr" -eq 0 ]; then
  pass "$ev"
else
  fail "$ev"
fi
