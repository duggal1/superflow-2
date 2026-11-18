#!/usr/bin/env bash
# Full completion audit — two consecutive passes, no code changes between.
# Each pass: lint + deps + every touched package + the app target.
set -u
cd /Users/harshitduggal/workspace/superflow || exit 1
OUT=.proof/quality/audit
mkdir -p "$OUT"
PACKAGES=(
  Packages/L2-Engines/TextLineFormat
  Packages/L2-Engines/TextNumbers
  Packages/L2-Engines/TextPipeline
  Packages/L2-Engines/TextCleanup
  Packages/L3-Features/FeatureIsland
  Packages/L3-Features/FeatureIntelligence
  Packages/L3-Features/FeatureDictionary
  Packages/L3-Features/FeatureShortcuts
  Packages/L3-Features/FeatureHistory
  Packages/L1-Adapters/StorageSQLite
  Packages/L2-Engines/AudioEnhancement
  Packages/L1-Adapters/AudioCapture
  Packages/L1-Adapters/SystemAudioCapture
  Packages/L1-Adapters/AudioCpp
  Packages/L1-Adapters/LLMLlamaCpp
  Packages/L2-Engines/RecoveryEngine
  App/SuperflowApp
)
FAILED=0
for pass in 1 2; do
  echo "===== PASS $pass =====" | tee "$OUT/pass$pass.txt"
  for i in $(seq 1 40); do
    if mkdir /tmp/superflow-build-lock 2>/dev/null; then break; fi
    sleep 5
  done
  tools/lint-forbidden >>"$OUT/pass$pass.txt" 2>&1; echo "lint rc=$?" | tee -a "$OUT/pass$pass.txt"
  tools/check-deps >>"$OUT/pass$pass.txt" 2>&1; echo "deps rc=$?" | tee -a "$OUT/pass$pass.txt"
  for p in "${PACKAGES[@]}"; do
    name=$(basename "$p")
    log="$OUT/pass$pass-$name.log"
    swift test --package-path "$p" --jobs 1 >"$log" 2>&1
    rc=$?
    line=$(grep -E 'Executed [0-9]+ tests' "$log" | tail -n 1)
    echo "$p rc=$rc $line" | tee -a "$OUT/pass$pass.txt"
    [ "$rc" -ne 0 ] && FAILED=$((FAILED+1))
  done
  rmdir /tmp/superflow-build-lock 2>/dev/null
done
echo "TOTAL_FAILING_RUNS=$FAILED" | tee -a "$OUT/summary.txt"
exit "$FAILED"
