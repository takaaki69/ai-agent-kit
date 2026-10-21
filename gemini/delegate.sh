#!/bin/bash
# Hand one task to the Gemini CLI (`gemini -p`, Google AI Pro via Google-account login).
#
#   bash gemini/delegate.sh [--write] [--model NAME] [--timeout SEC] "task"
#   bash gemini/delegate.sh [--write] --file prompt.md
#
# Without --write the run is read-only (plan mode). With --write it may edit files
# (auto_edit) but not run arbitrary shell commands. Auth: ~/.gemini/oauth_creds.json;
# in the cloud it comes from the kit's login store (lib/auth_store.py gemini).
set -uo pipefail
WRITE=0; MODEL="${GEMINI_DELEGATE_MODEL:-}"; TIMEOUT="${GEMINI_DELEGATE_TIMEOUT:-900}"; PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE=1 ;;
    --model) MODEL="$2"; shift ;;
    --timeout) TIMEOUT="$2"; shift ;;
    --file) PROMPT="$(cat "$2")"; shift ;;
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    *) PROMPT="${PROMPT:+$PROMPT }$1" ;;
  esac
  shift
done
[ -n "$PROMPT" ] || { echo "No task given." >&2; exit 2; }

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
AUTH=("$PY" "$KIT/lib/auth_store.py" gemini)
CLOUD=0; [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && CLOUD=1
command -v gemini >/dev/null 2>&1 || { echo "Gemini CLI not found. Run: bash $KIT/install.sh gemini" >&2; exit 3; }
if [ -z "${GEMINI_API_KEY:-}" ] && [ ! -s "$HOME/.gemini/oauth_creds.json" ]; then
  [ "$CLOUD" = 1 ] && (cd "$ROOT" && "${AUTH[@]}" restore) >&2
  [ -s "$HOME/.gemini/oauth_creds.json" ] || { echo "Gemini is not logged in. Run: bash $KIT/gemini/login.sh" >&2; exit 4; }
fi

RULES="You are working as a helper for another agent who will review your work.
Do not run git commit, git push, or delete files. Finish with a short summary:
what you changed (file paths) and anything you were unsure about."
[ "$WRITE" = 0 ] && RULES="$RULES
This is a read-only task: do not create or edit files; answer in text."
ARGS=(--skip-trust)
if [ "$WRITE" = 1 ]; then ARGS+=(--approval-mode auto_edit); else ARGS+=(--approval-mode plan); fi
[ -n "$MODEL" ] && ARGS+=(-m "$MODEL")
TIMEOUT_CMD=(); command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD=(timeout "$TIMEOUT")
LOG_DIR="$ROOT/.gemini-runs"; mkdir -p "$LOG_DIR"; LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"

# API keys in the environment would bypass the Google AI Pro login; drop them when a login exists.
ENVCMD=(env); [ -s "$HOME/.gemini/oauth_creds.json" ] && ENVCMD=(env -u GEMINI_API_KEY -u GOOGLE_API_KEY)
(cd "$ROOT" && "${ENVCMD[@]}" ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} gemini "${ARGS[@]}" -p "$RULES

Task:
$PROMPT") 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
echo
echo "==> gemini exit=$STATUS log=$LOG"
[ "$STATUS" = 124 ] && echo "==> timed out after ${TIMEOUT}s"
echo "==> changed files:"
git -C "$ROOT" status --short 2>/dev/null | grep -vE '\.(gemini|codex|cursor)-runs/' || true
[ "$CLOUD" = 1 ] && (cd "$ROOT" && "${AUTH[@]}" save) 2>&1 | sed 's/^/==> /'
exit "$STATUS"
