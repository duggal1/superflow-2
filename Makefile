
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
	app="$(CURDIR)/$(APP)"; \
	plist="$$app/Contents/Info.plist"; \
	if [ ! -f "$$plist" ]; then \
		echo "ERROR: $(APP) not found. Package the app first." >&2; \
		exit 1; \
	fi; \
	executable="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$$plist")"; \
	echo "Building latest Swift code (Release)..."; \
	swift build \
		--package-path "$(SWIFT_APP_PACKAGE)" \
		--configuration release; \
	bin_dir="$$(swift build \
		--package-path "$(SWIFT_APP_PACKAGE)" \
		--configuration release \
		--show-bin-path)"; \
	source_binary="$$bin_dir/$$executable"; \
	target_binary="$$app/Contents/MacOS/$$executable"; \
	if [ ! -x "$$source_binary" ]; then \
		echo "ERROR: Expected Swift executable not found: $$source_binary" >&2; \
		exit 1; \
	fi; \
	echo "Updating Superflow executable..."; \
	temp_binary="$$(mktemp "$$app/Contents/MacOS/.buildfix.XXXXXXXX")"; \
	trap 'rm -f "$$temp_binary"' EXIT; \
	cp "$$source_binary" "$$temp_binary"; \
	chmod 755 "$$temp_binary"; \
	mv -f "$$temp_binary" "$$target_binary"; \
	echo "Updated: $$target_binary"; \
	echo "Swift build completed. Rust and caches preserved."

app: buildfix

run: SHELL := /bin/bash
run:
	@set -euo pipefail; \
	latest=""; latest_time=0; \
	while IFS= read -r -d '' binary; do \
		time="$$(stat -f %m "$$binary")"; \
		if [ -z "$$latest" ] || [ "$$time" -gt "$$latest_time" ]; then \
			latest="$$binary"; latest_time="$$time"; \
		fi; \
	done < <(find App/SuperflowApp/.build dist -type f -name SuperflowApp -perm +111 -print0 2>/dev/null || true); \
	if [ -z "$$latest" ]; then \
		echo "ERROR: No SuperflowApp binary found." >&2; exit 1; \
	fi; \
	echo "Opening $$latest"; \
	case "$$latest" in \
		*.app/Contents/MacOS/SuperflowApp) open "$${latest%/Contents/MacOS/SuperflowApp}" ;; \
		*) open "$$latest" ;; \
	esac
