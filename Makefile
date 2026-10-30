
# ------------------------------------------------------------
# SWIFT BUILD
# Recompile changed Swift code and update the app executable.
# Never clean Rust, SwiftPM caches, models, or dependencies.
# ------------------------------------------------------------

.PHONY: build buildfix app run

APP := dist/Superflow.app
SWIFT_APP_PACKAGE := App/SuperflowApp

build: buildfix

buildfix:
	@set -euo pipefail; \
	if [ -z "$${SUPERFLOW_SIGN_IDENTITY:-}" ]; then tools/dev-signing --print >/dev/null; fi; \
	swift build --package-path "$(SWIFT_APP_PACKAGE)" --configuration release; \
	bin_dir="$$(swift build --package-path "$(SWIFT_APP_PACKAGE)" --configuration release --show-bin-path)"; \
	CONFIGURATION=release SUPERFLOW_BIN_DIR="$$bin_dir" tools/package-app --skip-build

app: buildfix

run: app
	@codesign --verify --deep --strict "$(APP)"
	@open "$(APP)"
