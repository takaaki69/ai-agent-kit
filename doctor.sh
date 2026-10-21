#!/bin/bash
# Check that this environment is ready to use the kit, and say exactly what to fix.
#   bash doctor.sh            # all three
#   bash doctor.sh codex agy  # only some
# Exit 0 = ready, 1 = something is missing (see the "TODO" lines). Prints no secrets.
set -uo pipefail
export PATH="$HOME/.local/bin:$PATH"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
WANT=("$@"); [ ${#WANT[@]} -gt 0 ] || WANT=(codex cursor agy)
BAD=0
ok()   { echo "OK    $*"; }
todo() { echo "TODO  $1"; shift; for l in "$@"; do echo "        $l"; done; BAD=1; }
want() { local t; for t in "${WANT[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
restore() { [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && (cd "$ROOT" && "$PY" "$KIT/lib/auth_store.py" "$1" restore) >/dev/null 2>&1; }

# Is the project's environment setup calling the kit's install.sh?
if grep -rqs "ai-agent-kit" "$ROOT/.claude" "$ROOT/scripts/cloud" 2>/dev/null; then
  ok "project setup mentions ai-agent-kit"
else
  todo "The project's environment setup does not call the kit's install.sh." \
       "Where: the project's setup script (e.g. scripts/cloud/setup.sh) or the cloud environment's Setup script." \
       "Add: bash $KIT/install.sh   (and keep ai-agent-kit in the project's Repositories)"
fi

STORE="$(cd "$ROOT" && python3 "$KIT/lib/auth_store.py" codex store 2>/dev/null)"
case "$STORE" in
  drive*|"dir (AI_KIT_STORE)") ok "login store: $STORE" ;;
  *) todo "Codex/agy logins are lost when the session ends (login store: ${STORE:-unknown})." \
          "Where: cloud environment settings -> Environment variables." \
          "Add the 4 Drive variables (same values as the OPENMONTAGE_DRIVE_* ones in montage-studio's environment):" \
          "  AI_KIT_DRIVE_CLIENT_ID, AI_KIT_DRIVE_CLIENT_SECRET, AI_KIT_DRIVE_REFRESH_TOKEN, AI_KIT_DRIVE_ROOT_FOLDER_ID" \
          "(Never paste the values in chat. A project that already has <PREFIX>_DRIVE_* variables needs nothing.)" \
          "Without Drive: AI_KIT_STORE=dir:<a synced folder that survives sessions>" ;;
esac

if want codex; then
  if ! command -v codex >/dev/null 2>&1; then todo "Codex CLI is not installed." "Run: bash $KIT/install.sh codex"
  else
    codex login status >/dev/null 2>&1 || restore codex
    if codex login status >/dev/null 2>&1; then ok "Codex logged in"
    else todo "Codex is not logged in (first time only)." \
              "Claude runs: bash $KIT/codex/login.sh  (in the background)" \
              "Takaaki: open https://auth.openai.com/codex/device and enter the code Claude shows."
    fi
  fi
fi

if want cursor; then
  if ! command -v agent >/dev/null 2>&1 && ! command -v cursor-agent >/dev/null 2>&1; then
    todo "Cursor CLI is not installed." "Run: bash $KIT/install.sh cursor"
  else ok "Cursor CLI installed"; fi
  if [ -n "${CURSOR_API_KEY:-}" ]; then ok "CURSOR_API_KEY is set"
  else todo "CURSOR_API_KEY is not set." \
            "Where: cloud environment settings -> Environment variables (never paste the key in chat)." \
            "Add: CURSOR_API_KEY=<key from Cursor dashboard -> Integrations / API keys>"
  fi
fi

if want agy; then
  TOKEN="${AGY_AUTH_DIR:-$HOME/.gemini/antigravity-cli}/antigravity-oauth-token"
  if ! command -v agy >/dev/null 2>&1; then todo "agy (Antigravity CLI) is not installed." "Run: bash $KIT/install.sh agy"
  else
    [ -s "$TOKEN" ] || restore agy
    if [ -s "$TOKEN" ]; then ok "agy logged in"
    else todo "agy is not logged in (first time only; needs the Google AI Pro account)." \
              "Claude runs: python3 $KIT/agy/login_headless.py start   (prints a URL)" \
              "Takaaki: open the URL, sign in, paste back the code." \
              "Claude runs: python3 $KIT/agy/login_headless.py code <code>"
    fi
  fi
fi

[ "$BAD" = 0 ] && echo "All set." || echo "Not ready: tell Takaaki the TODO items above, with the places and steps."
exit "$BAD"
