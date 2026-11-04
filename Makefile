
# ------------------------------------------------------------
# SWIFT BUILD
# Recompile changed Swift code and update the app executable.
# Never clean Rust, SwiftPM caches, models, or dependencies.
# ------------------------------------------------------------

.PHONY: build buildfix app run test lint verify deps-check lint-forbidden native-audio

APP := dist/Superflow.app
SWIFT_APP_PACKAGE := App/SuperflowApp

SWIFT_PACKAGE_ROOTS := Packages App/SuperflowApp App/InferenceHelper
EXCLUDED_PACKAGE_DIRS := -name .build -prune -o -name .git -prune -o -name .swiftpm -prune -o -name checkouts -prune -o -name artifacts -prune -o -name SourcePackages -prune -o

SWIFT_PACKAGES := $(shell find $(SWIFT_PACKAGE_ROOTS) $(EXCLUDED_PACKAGE_DIRS) -name Package.swift -print 2>/dev/null | sort)
SWIFT_TEST_PACKAGES := $(shell for manifest in $(SWIFT_PACKAGES); do grep -q '\.testTarget' "$$manifest" && printf '%s\n' "$$manifest"; done)

build: buildfix

native-audio:
	@./tools/build-audio-cpp

buildfix: native-audio
	@set -euo pipefail; \
	if [ -z "$${SUPERFLOW_SIGN_IDENTITY:-}" ]; then tools/dev-signing --print >/dev/null; fi; \
	swift build --package-path "$(SWIFT_APP_PACKAGE)" --configuration release; \
	bin_dir="$$(swift build --package-path "$(SWIFT_APP_PACKAGE)" --configuration release --show-bin-path)"; \
	CONFIGURATION=release SUPERFLOW_BIN_DIR="$$bin_dir" tools/package-app --skip-build

app: buildfix

run: app
	@codesign --verify --deep --strict "$(APP)"
	@open "$(APP)"

# ------------------------------------------------------------
# TESTS AND CHECKS
# `verify` is the phase/release gate named in AGENTS.md and CI.
# It must work without a signing identity: no packaging here.
# ------------------------------------------------------------

test: native-audio
	@set -euo pipefail; \
	for manifest in $(SWIFT_TEST_PACKAGES); do \
		printf '==> %s\n' "$$(dirname "$$manifest")"; \
		swift test --package-path "$$(dirname "$$manifest")"; \
	done

lint: deps-check lint-forbidden

deps-check:
	@./tools/check-deps
	@bash ./tools/test-check-deps

lint-forbidden:
	@./tools/lint-forbidden

verify: lint test
	@swift build --package-path $(SWIFT_APP_PACKAGE)
