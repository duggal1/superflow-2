#!/usr/bin/env bash
# R19: aggressive testing (happy/edge/hostile/repeat/states/aftermath), two screenshot
#      review passes with fixes, completion audit two consecutive clean passes.
# PASS requires REAL PNG artefacts in BOTH passes (not just prose in a markdown file).
source "$(dirname "$0")/_lib.sh"
v="$ROOT/.proof/validation"
sr="$v/screenshot-review.md"
rep="$v/report.md"
p1=$(find "$v/screens/pass1" -type f -name '*.png' -size +0c 2>/dev/null | wc -l | tr -d ' ')
p2=$(find "$v/screens/pass2" -type f -name '*.png' -size +0c 2>/dev/null | wc -l | tr -d ' ')
reviewed=0; fixed=0; two=0
[ -f "$sr" ] && grep -qiE 'pass 1|first pass' "$sr" && grep -qiE 'pass 2|second pass' "$sr" && reviewed=1
[ -f "$sr" ] && grep -qiE 'fix|changed|requested' "$sr" && fixed=1
[ -f "$rep" ] && grep -qE '^AUDIT_PASSES=2' "$rep" && two=1
if [ "$p1" -gt 0 ] && [ "$p2" -gt 0 ] && [ "$reviewed" -eq 1 ] && [ "$fixed" -eq 1 ] && [ "$two" -eq 1 ]; then
  pass "REAL screenshots: pass1=$p1 PNGs, pass2=$p2 PNGs (non-empty); screenshot-review has both passes=$reviewed fixes=$fixed; report.md AUDIT_PASSES=2=$two"
else
  fail "pass1 PNGs=$p1 pass2 PNGs=$p2 reviewed=$reviewed fixes=$fixed audit-passes-2=$two — real images in both passes + two clean audits required"
fi
