.PHONY: app build test run clean

CLANG_MODULE_CACHE_PATH ?= /tmp/clang-module-cache
SWIFTPM_MODULECACHE_OVERRIDE ?= /tmp/swift-module-cache

app:
	./scripts/build-app.sh

build:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) swift build --disable-sandbox -Xswiftc -module-cache-path -Xswiftc $(SWIFTPM_MODULECACHE_OVERRIDE)

test:
	CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_PATH) SWIFTPM_MODULECACHE_OVERRIDE=$(SWIFTPM_MODULECACHE_OVERRIDE) swift test --disable-sandbox -Xswiftc -module-cache-path -Xswiftc $(SWIFTPM_MODULECACHE_OVERRIDE)

run: app
	open ./build/OpenBetterDisplay.app

clean:
	rm -rf .build build
