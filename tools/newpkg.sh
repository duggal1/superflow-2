#!/bin/bash
# newpkg.sh <Layer> <Name> "<dep paths...>" [--resources] [--extra-pkg <line>] [--extra-target <line>]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAYER=$1; NAME=$2; DEPS=${3:-}; shift 3 || true
RES=""; EXTRAPKG=""; EXTRATARGET=""; DIRNAME=$NAME
while [ $# -gt 0 ]; do
  case "$1" in
    --resources) RES=', resources: [.copy("Resources")]'; mkdir -p "$ROOT/Packages/$LAYER/$NAME/Sources/Superflow$NAME/Resources"; shift;;
    --extra-pkg) EXTRAPKG="$2"; shift 2;;
    --extra-target) EXTRATARGET="$2"; shift 2;;
    --dir) DIRNAME="$2"; shift 2;;
    *) echo "unknown flag $1"; exit 1;;
  esac
done
D="$ROOT/Packages/$LAYER/$DIRNAME"
mkdir -p "$D/Sources/Superflow$NAME" "$D/Tests/${NAME}Tests"
PK=""; TG=""; TESTTG=""
for x in $DEPS; do
  n=${x#*/}
  PK+="        .package(path: \"../../$x\"),"$'\n'
  TG+="                .product(name: \"Superflow$n\", package: \"$n\"),"$'\n'
  TESTTG+="                .product(name: \"Superflow$n\", package: \"$n\"),"$'\n'
done
cat > "$D/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "$NAME",
    platforms: [.macOS(.v15)],
    products: [.library(name: "Superflow$NAME", targets: ["Superflow$NAME"])],
    dependencies: [
$PK$EXTRAPKG    ],
    targets: [
        .target(
            name: "Superflow$NAME",
            dependencies: [
$TG$EXTRATARGET            ]$RES
        ),
        .testTarget(
            name: "Superflow${NAME}Tests",
            dependencies: [
                "Superflow$NAME",
$TESTTG            ],
            path: "Tests/${NAME}Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
EOF
