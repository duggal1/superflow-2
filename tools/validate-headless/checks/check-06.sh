#!/usr/bin/env bash
# R6: attached top-center borderless non-activating NSPanel; safeAreaInsets/auxiliary;
#     all Spaces/fullscreen; frame never animates; one continuous silhouette.
# PASS requires flag source AND a real IslandPanelController XCTest exercise.
source "$(dirname "$0")/_lib.sh"
f="$ROOT/App/SuperflowApp/Sources/SuperflowAppCore/Windowing/IslandPanelController.swift"
geo="$ROOT/Packages/L3-Features/FeatureIsland/Sources/SuperflowFeatureIsland/NotchGeometry.swift"
[ -f "$f" ] || source_only "IslandPanelController.swift missing"
pats=( '.borderless' '.nonactivatingPanel' 'sharingType' '.canJoinAllSpaces' '.fullScreenAuxiliary' 'setFrame' 'display: false' 'constrainFrameRect' )
found=(); miss=()
for p in "${pats[@]}"; do grep -qF "$p" "$f" && found+=("$p") || miss+=("$p"); done
geopats=( 'safeAreaInsets' 'auxiliaryTopLeftArea' 'auxiliaryTopRightArea' )
geofound=(); geomiss=()
for p in "${geopats[@]}"; do grep -qF "$p" "$geo" && geofound+=("$p") || geomiss+=("$p"); done

ex=$(test_exercise "App/SuperflowApp" "IslandPanelController" "panel-controller") && exok=1 || exok=0
if [ ${#miss[@]} -eq 0 ] && [ ${#geomiss[@]} -eq 0 ] && [ "$exok" -eq 1 ]; then
  pass "NSPanel flags=$(join_ev "${found[@]}"); notch geometry=$(join_ev "${geofound[@]}"); EXERCISED panel controller: $ex"
else
  fail "flags_missing={$(join_ev "${miss[@]:-none}")} geometry_missing={$(join_ev "${geomiss[@]:-none}")} exercise_ok=$exok; $ex"
fi
