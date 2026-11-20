#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$(git -C "${ROOT_DIR}" rev-parse --git-path hooks)"
HOOK_PATH="${HOOKS_DIR}/pre-commit"

mkdir -p "${HOOKS_DIR}"
cat > "${HOOK_PATH}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec make check
EOF
chmod +x "${HOOK_PATH}"
echo "Installed pre-commit hook at ${HOOK_PATH}"
