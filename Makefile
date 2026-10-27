SHELL := /bin/bash

SWIFT_PACKAGE_ROOTS := Packages App/SuperflowApp App/InferenceHelper tools/Superflowctl
EXCLUDED_PACKAGE_DIRS := -name .build -prune -o -name .git -prune -o -name .swiftpm -prune -o -name checkouts -prune -o -name artifacts -prune -o -name SourcePackages -prune -o
SWIFT_PACKAGES := $(shell find $(SWIFT_PACKAGE_ROOTS) $(EXCLUDED_PACKAGE_DIRS) -name Package.swift -print 2>/dev/null | sort)
SWIFT_TEST_PACKAGES := $(shell for manifest in $(SWIFT_PACKAGES); do grep -q '\.testTarget' "$$manifest" && printf '%s\n' "$$manifest"; done)
FAST_SWIFT_TEST_PACKAGES := $(filter-out %/ASRFluidAudio/Package.swift %/DiarizationFluidAudio/Package.swift %/LLMLlamaCpp/Package.swift %/GrammarHarper/Package.swift App/SuperflowApp/Package.swift tools/Superflowctl/Package.swift,$(SWIFT_TEST_PACKAGES))
MODEL_TEST_PACKAGES := $(foreach module,ASRFluidAudio DiarizationFluidAudio LLMLlamaCpp GrammarHarper,Packages/L1-Adapters/$(module)/Package.swift)
FAST_TEST_PACKAGES := Tests/Golden/Package.swift
ALL_TEST_PACKAGES := $(shell find Tests/Integration Tests/Golden Tests/Soak $(EXCLUDED_PACKAGE_DIRS) -name Package.swift -print 2>/dev/null | sort)

.PHONY: app app-smoke run build test test-fast test-models lint lint-forbidden deps-check verify soak soak-10h soak-realtime gen-fixture harper dmg sign notarize release

app:
	@./tools/package-app

app-smoke:
	@./tools/test-package-app

# Build if needed, then launch the assembled bundle.
run: app
	@open dist/Superflow.app

dmg: app
	@./tools/package-dmg

sign:
	@./tools/notarize

notarize:
	@./tools/notarize

release: dmg
	@./tools/notarize

build:
	@set -eu; for manifest in $(SWIFT_PACKAGES); do swift build --package-path "$$(dirname "$$manifest")"; done

test:
	@set -eu; for manifest in $(SWIFT_TEST_PACKAGES) $(ALL_TEST_PACKAGES); do swift test --package-path "$$(dirname "$$manifest")"; done

test-fast:
	@set -eu; for manifest in $(FAST_SWIFT_TEST_PACKAGES) $(FAST_TEST_PACKAGES); do swift test --package-path "$$(dirname "$$manifest")"; done

test-models:
	@set -eu; for manifest in $(MODEL_TEST_PACKAGES); do swift test --package-path "$$(dirname "$$manifest")"; done

lint: deps-check lint-forbidden

deps-check:
	@./tools/check-deps
	@bash ./tools/test-check-deps
	@python3 ./tools/dependency-graph.py --output docs/architecture/module-dependencies.mmd

lint-forbidden:
	@./tools/lint-forbidden

verify: build test lint

soak:
	@SUPERFLOW_SOAK_SECONDS="$${SUPERFLOW_SOAK_SECONDS:-3600}" swift test --package-path Tests/Soak

soak-10h:
	@SUPERFLOW_SOAK_SECONDS=36000 swift test --package-path Tests/Soak

soak-realtime:
	@SUPERFLOW_SOAK_SECONDS="$${SUPERFLOW_SOAK_SECONDS:-36000}" SUPERFLOW_SOAK_REALTIME=1 swift test --package-path Tests/Soak

gen-fixture:
	@test -n "$(OUTPUT)" || { printf '%s\n' 'Usage: make gen-fixture OUTPUT=/path/to/audio.wav SECONDS=3600' >&2; exit 2; }
	@test -n "$(SECONDS)" || { printf '%s\n' 'Set SECONDS to the fixture duration.' >&2; exit 2; }
	@python3 tools/gen-fixtures/generate_audio.py "$(OUTPUT)" --seconds "$(SECONDS)"

harper:
	@set -eu; cd Rust/harper-ffi && cargo build --release
	@rm -rf Rust/harper-ffi/HarperFFI.xcframework
	@mkdir -p Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64
	@cp Rust/harper-ffi/target/release/libharper_ffi.a Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/libharper_ffi.a
	@mkdir -p Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers
	@cp Rust/harper-ffi/include/harper_ffi.h Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers/
	@cp Rust/harper-ffi/include/module.modulemap Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers/module.modulemap
	@/usr/bin/xcodebuild -create-xcframework -library Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/libharper_ffi.a -headers Rust/harper-ffi/HarperFFI.xcframework/macos-arm64_x86_64/Headers -output Rust/harper-ffi/HarperFFI.tmp.xcframework
	@rm -rf Rust/harper-ffi/HarperFFI.xcframework
	@mv Rust/harper-ffi/HarperFFI.tmp.xcframework Rust/harper-ffi/HarperFFI.xcframework
