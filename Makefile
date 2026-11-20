.PHONY: app build test test-quiet check format preview install-hooks run clean

WORKTREE_ID := $(notdir $(CURDIR))
CLANG_MODULE_CACHE_PATH ?= /tmp/obd-$(WORKTREE_ID)-clang
SWIFTPM_MODULECACHE_OVERRIDE ?= /tmp/obd-$(WORKTREE_ID)-swift
PREVIEW_OUT ?= /tmp/openbetterdisplay-preview.png

app:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) ./scripts/build-app.sh

build:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) swift build --disable-sandbox -Xswiftc -module-cache-path -Xswiftc $(SWIFTPM_MODULECACHE_OVERRIDE)

test:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) swift test --disable-sandbox -Xswiftc -module-cache-path -Xswiftc $(SWIFTPM_MODULECACHE_OVERRIDE)

test-quiet:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) ./scripts/test-quiet.sh

check:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) ./scripts/check.sh

format:
	swift format --in-place --parallel --configuration .swift-format --recursive Sources Tests Tools

preview:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) swift run --disable-sandbox -Xswiftc -module-cache-path -Xswiftc $(SWIFTPM_MODULECACHE_OVERRIDE) PopoverPreview $(PREVIEW_OUT)

install-hooks:
	./scripts/install-hooks.sh

run: app
	open ./build/OpenBetterDisplay.app

clean:
	rm -rf .build build
