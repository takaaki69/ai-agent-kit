#!/bin/bash
# Log the cloud's Gemini CLI in with the Google account (AI Pro), then keep the
# login in the kit's store. Needed once. Gemini prints a URL; open it in a browser,
# sign in, and paste the code it shows back into the CLI.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
cd "$ROOT"
mkdir -p "$HOME/.gemini"
SETTINGS="$HOME/.gemini/settings.json"
[ -f "$SETTINGS" ] || echo '{"security":{"auth":{"selectedType":"oauth-personal"}}}' > "$SETTINGS"

if [ -s "$HOME/.gemini/oauth_creds.json" ]; then
  echo "Gemini already has a login."
else
  echo "Starting Gemini; sign in when it asks, then type /quit."
  NO_BROWSER=true gemini || exit $?
fi
if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  "$PY" "$KIT/lib/auth_store.py" gemini save
fi
