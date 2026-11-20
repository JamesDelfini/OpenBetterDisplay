#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_ID="$(basename "${ROOT_DIR}")"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/obd-${WORKTREE_ID}-clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/obd-${WORKTREE_ID}-swift}"

echo "==> Checking for leftover debug tags..."
if grep -rn "\[DEBUG-" "${ROOT_DIR}/Sources" "${ROOT_DIR}/Tests" "${ROOT_DIR}/Tools" 2>/dev/null; then
    echo "error: leftover [DEBUG-...] instrumentation tag found" >&2
    exit 1
fi

echo "==> Checking that test doubles stay out of Sources/..."
if find "${ROOT_DIR}/Sources" -type f \( -name "Fake*.swift" -o -name "Mock*.swift" -o -name "Stub*.swift" \) | grep -q .; then
    echo "error: test double file found inside Sources/" >&2
    exit 1
fi
if grep -rnE "\b(final )?(class|struct|enum) (Fake|Mock|Stub|InMemory)[A-Z]" "${ROOT_DIR}/Sources" 2>/dev/null; then
    echo "error: test double type declared inside Sources/" >&2
    exit 1
fi

echo "==> Running swift format lint (strict)..."
swift format lint \
    --strict \
    --parallel \
    --configuration "${ROOT_DIR}/.swift-format" \
    --recursive \
    "${ROOT_DIR}/Sources" \
    "${ROOT_DIR}/Tests" \
    "${ROOT_DIR}/Tools"

echo "==> Building with warnings-as-errors..."
swift build \
    --disable-sandbox \
    --package-path "${ROOT_DIR}" \
    -Xswiftc -warnings-as-errors \
    -Xswiftc -module-cache-path \
    -Xswiftc "${SWIFTPM_MODULECACHE_OVERRIDE}"

echo "==> Running tests..."
"${ROOT_DIR}/scripts/test-quiet.sh"

echo "==> All checks passed."
