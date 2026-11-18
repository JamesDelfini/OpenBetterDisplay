#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="OpenBetterDisplay"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/clang-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/swift-module-cache}"

echo "==> Building ${APP_NAME} (${CONFIGURATION})..."
swift build \
    --disable-sandbox \
    --package-path "${ROOT_DIR}" \
    -c "${CONFIGURATION}" \
    -Xswiftc -module-cache-path \
    -Xswiftc "${SWIFTPM_MODULECACHE_OVERRIDE}"

BIN_PATH="$(swift build \
    --disable-sandbox \
    --package-path "${ROOT_DIR}" \
    -c "${CONFIGURATION}" \
    --show-bin-path)/${APP_NAME}"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>OpenBetterDisplay</string>
    <key>CFBundleExecutable</key>
    <string>OpenBetterDisplay</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.openbetterdisplay.OpenBetterDisplay</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OpenBetterDisplay</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true
fi

echo "==> Packaged ${APP_BUNDLE}"
