#!/bin/bash
# Log the cloud's Codex CLI in with the ChatGPT plan, then keep the login in the kit's store.
# Needed once (and again only if the login stops working). Prints a code to
# approve at https://auth.openai.com/codex/device.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
cd "$ROOT"

if codex login status >/dev/null 2>&1; then
  echo "Codex is already logged in."
else
  codex login --device-auth || exit $?
fi
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  "$PY" "$KIT/lib/auth_store.py" codex save
fi
