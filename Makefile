
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

APP := dist/Superflow.app

SWIFT_PACKAGE_ROOTS := Packages App/SuperflowApp App/InferenceHelper tools/Superflowctl

EXCLUDED_PACKAGE_DIRS := -name .build -prune -o -name .git -prune -o -name .swiftpm -prune -o -name checkouts -prune -o -name artifacts -prune -o -name SourcePackages -prune -o

SWIFT_PACKAGES := $(shell find $(SWIFT_PACKAGE_ROOTS) $(EXCLUDED_PACKAGE_DIRS) -name Package.swift -print 2>/dev/null | sort)

SWIFT_TEST_PACKAGES := $(shell for manifest in $(SWIFT_PACKAGES); do grep -q '\.testTarget' "$$manifest" && printf '%s\n' "$$manifest"; done)

FAST_SWIFT_TEST_PACKAGES := $(filter-out %/ASRFluidAudio/Package.swift %/DiarizationFluidAudio/Package.swift %/LLMLlamaCpp/Package.swift %/GrammarHarper/Package.swift App/SuperflowApp/Package.swift tools/Superflowctl/Package.swift,$(SWIFT_TEST_PACKAGES))

MODEL_TEST_PACKAGES := $(foreach module,ASRFluidAudio DiarizationFluidAudio LLMLlamaCpp GrammarHarper,Packages/L1-Adapters/$(module)/Package.swift)

FAST_TEST_PACKAGES := Tests/Golden/Package.swift

ALL_TEST_PACKAGES := $(shell find Tests/Integration Tests/Golden Tests/Soak $(EXCLUDED_PACKAGE_DIRS) -name Package.swift -print 2>/dev/null | sort)

CLEAN_JOBS ?= $(shell sysctl -n hw.logicalcpu 2>/dev/null || echo 8)

.PHONY: app app-smoke run build clean test test-fast test-models lint lint-forbidden deps-check verify soak soak-10h soak-realtime gen-fixture harper dmg sign notarize release


# ------------------------------------------------------------
# BUILD
# Force fresh Swift and Rust compilation, then package the app.
# Preserve the previous packaged app if packaging fails.
# ------------------------------------------------------------

build:
	@echo "Cleaning Swift compilation artifacts..."
	@for manifest in $(SWIFT_PACKAGES); do \
		swift package --package-path "$$(dirname "$$manifest")" clean; \
	done
	@echo "Cleaning Rust compilation artifacts..."
	@cargo clean --manifest-path Rust/harper-ffi/Cargo.toml
	@echo "Rebuilding Rust framework..."
	@$(MAKE) --no-print-directory harper
	@echo "Compiling Swift packages (Release)..."
	@for manifest in $(SWIFT_PACKAGES); do \
		swift build -c release --package-path "$$(dirname "$$manifest")"; \
	done
	@echo "Packaging fresh macOS application..."
	@mkdir -p dist
	@backup="$$(mktemp -d "$(CURDIR)/.superflow-backup.XXXXXX")"; \
	restore() { \
		status="$$?"; \
		if [ "$$status" -ne 0 ]; then \
			rm -rf "$(APP)"; \
			if [ -d "$$backup/Superflow.app" ]; then \
				mv "$$backup/Superflow.app" "$(APP)"; \
			fi; \
		fi; \
		rm -rf "$$backup"; \
		exit "$$status"; \
	}; \
	trap restore EXIT; \
	if [ -d "$(APP)" ]; then \
		mv "$(APP)" "$$backup/Superflow.app"; \
	fi; \
	./tools/package-app; \
	test -f "$(APP)/Contents/Info.plist" || { \
		echo "ERROR: Application bundle was not created." >&2; \
		exit 1; \
	}; \
	executable="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$(APP)/Contents/Info.plist")"; \
	test -x "$(APP)/Contents/MacOS/$$executable" || { \
		echo "ERROR: Application executable is missing." >&2; \
		exit 1; \
	}; \
	echo "Fresh application built: $(APP)"


# ------------------------------------------------------------
# RUN
# Open the existing app. No compilation or packaging.
# ------------------------------------------------------------

run:
	@test -d "$(APP)" || { \
		echo "Application not found. Run: sf build" >&2; \
		exit 1; \
	}
	@open "$(APP)"


# ------------------------------------------------------------
# CLEAN
# Parallel deletion of SwiftPM .build directories only.
# Keeps source, models, Rust target and dist/Superflow.app.
# ------------------------------------------------------------

clean:
	@echo "Removing SwiftPM .build directories..."
	@echo "Parallel workers: $(CLEAN_JOBS)"
	@find . \
		-type d \( \
			-name .git -o \
			-name node_modules -o \
			-name dist -o \
			-name .next -o \
			-name target \
		\) -prune -o \
		-type d -name .build -prune -print0 \
		| xargs -0 -P "$(CLEAN_JOBS)" -n 1 rm -rf --
	@echo "SwiftPM build directories removed."


# ------------------------------------------------------------
# APP
# ------------------------------------------------------------

app: build

app-smoke:
	@./tools/test-package-app


# ------------------------------------------------------------
# DISTRIBUTION
# ------------------------------------------------------------

dmg: build
	@./tools/package-dmg

sign:
	@./tools/notarize

notarize:
	@./tools/notarize

release: dmg
	@./tools/notarize


# ------------------------------------------------------------
# TESTS
# ------------------------------------------------------------

test:
	@for manifest in $(SWIFT_TEST_PACKAGES) $(ALL_TEST_PACKAGES); do \
		swift test --package-path "$$(dirname "$$manifest")"; \
	done

test-fast:
	@for manifest in $(FAST_SWIFT_TEST_PACKAGES) $(FAST_TEST_PACKAGES); do \
		swift test --package-path "$$(dirname "$$manifest")"; \
	done

test-models:
	@for manifest in $(MODEL_TEST_PACKAGES); do \
		swift test --package-path "$$(dirname "$$manifest")"; \
	done


# ------------------------------------------------------------
# LINT AND DEPENDENCY CHECKS
# ------------------------------------------------------------

lint: deps-check lint-forbidden

deps-check:
	@./tools/check-deps
	@bash ./tools/test-check-deps
	@python3 ./tools/dependency-graph.py --output docs/architecture/module-dependencies.mmd

lint-forbidden:
	@./tools/lint-forbidden

verify: build test lint


# ------------------------------------------------------------
# SOAK TESTS
# ------------------------------------------------------------

soak:
	@SUPERFLOW_SOAK_SECONDS="$${SUPERFLOW_SOAK_SECONDS:-3600}" swift test --package-path Tests/Soak

soak-10h:
	@SUPERFLOW_SOAK_SECONDS=36000 swift test --package-path Tests/Soak

soak-realtime:
	@SUPERFLOW_SOAK_SECONDS="$${SUPERFLOW_SOAK_SECONDS:-36000}" SUPERFLOW_SOAK_REALTIME=1 swift test --package-path Tests/Soak


# ------------------------------------------------------------
# FIXTURE GENERATION
# ------------------------------------------------------------

gen-fixture:
	@test -n "$(OUTPUT)" || { \
		echo "Usage: make gen-fixture OUTPUT=/path/to/audio.wav SECONDS=3600" >&2; \
		exit 2; \
	}
	@test -n "$(SECONDS)" || { \
		echo "Set SECONDS to the fixture duration." >&2; \
		exit 2; \
	}
	@python3 tools/gen-fixtures/generate_audio.py "$(OUTPUT)" --seconds "$(SECONDS)"


# ------------------------------------------------------------
# RUST / HARPER FFI
# ------------------------------------------------------------

harper:
	@cd Rust/harper-ffi && cargo build --release
	@rm -rf Rust/harper-ffi/HarperFFI.xcframework
	@mkdir -p Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64
	@cp Rust/harper-ffi/target/release/libharper_ffi.a Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/libharper_ffi.a
	@mkdir -p Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers
	@cp Rust/harper-ffi/include/harper_ffi.h Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers/
	@cp Rust/harper-ffi/include/module.modulemap Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers/module.modulemap
	@/usr/bin/xcodebuild -create-xcframework \
		-library Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/libharper_ffi.a \
		-headers Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers \
		-output Rust/harper-ffi/HarperFFI.tmp.xcframework
	@rm -rf Rust/harper-ffi/HarperFFI.xcframework
	@mv Rust/harper-ffi/HarperFFI.tmp.xcframework Rust/harper-ffi/HarperFFI.xcframework
