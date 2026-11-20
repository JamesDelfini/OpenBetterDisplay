#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_ID="$(basename "${ROOT_DIR}")"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/obd-${WORKTREE_ID}-clang}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/obd-${WORKTREE_ID}-swift}"

LOG_FILE="$(mktemp "/tmp/obd-test-${WORKTREE_ID}.XXXXXX")"
trap 'rm -f "${LOG_FILE}"' EXIT

set +e
swift test \
    --disable-sandbox \
    --package-path "${ROOT_DIR}" \
    -Xswiftc -module-cache-path \
    -Xswiftc "${SWIFTPM_MODULECACHE_OVERRIDE}" \
    "$@" >"${LOG_FILE}" 2>&1
STATUS=$?
set -e

if [[ "${STATUS}" -ne 0 ]]; then
    cat "${LOG_FILE}"
    exit "${STATUS}"
fi

grep -E "^(Build complete!|Test Suite '.*' passed|	 Executed [0-9]+ test|✔ Test run)" "${LOG_FILE}" || cat "${LOG_FILE}"
