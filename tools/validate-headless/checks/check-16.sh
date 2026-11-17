#!/usr/bin/env bash
# R16: Output view fully expanded, selectable/copyable text, Markdown with copyable
#      code blocks, scrolls inside Island, capped height.
# Old check grepped only FeatureIsland, but Markdown lives in FeatureIntelligence
# (false FAIL). PASS requires the real implementation AND a real answer-view exercise.
source "$(dirname "$0")/_lib.sh"
src="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland $ROOT/Packages/L3-Features/FeatureIntelligence/Sources/SuperflowFeatureIntelligence"
sel=$(grep -rE 'textSelection\(\.enabled\)' $src 2>/dev/null | wc -l | tr -d ' ')
md=$(rg -n -i 'markdown|codeblock|fenced' $src -g '*.swift' 2>/dev/null | wc -l | tr -d ' ')
scroll=$(grep -rE 'ScrollView' $src 2>/dev/null | wc -l | tr -d ' ')
cap=$(grep -rE 'maxHeight|frame\(height:|cappedHeight' $src 2>/dev/null | wc -l | tr -d ' ')
mdfile=$(rg -l 'MarkdownAnswer' $src -g '*.swift' 2>/dev/null | head -1)

ex=$(test_exercise "App/SuperflowApp" "HeadlessIntelligenceComposeTests" "answer-view") && exok=1 || exok=0
if [ "$sel" -gt 0 ] && [ "$md" -gt 0 ] && [ "$scroll" -gt 0 ] && [ "$cap" -gt 0 ] && [ "$exok" -eq 1 ]; then
  pass "selectable=$sel markdown/code=$md (${mdfile#$ROOT/}) scroll=$scroll capped=$cap; EXERCISED answer/compose view: $ex"
else
  fail "selectable=$sel markdown=$md scroll=$scroll cap=$cap exercise_ok=$exok; $ex"
fi
