#!/bin/bash
# Hand one task to the Antigravity CLI (`agy`, Google AI Pro via Google-account login).
# agy replaced the Gemini CLI for personal Google accounts on 2026-06-18.
#
#   bash agy/delegate.sh [--write] [--model NAME] [--timeout SEC] "task"
#   bash agy/delegate.sh [--write] --file prompt.md
#
# Without --write the run is read-only (plan mode). With --write it may edit files
# (accept-edits mode). Auth: ~/.gemini/antigravity-cli/antigravity-oauth-token; in the
# cloud it comes from the kit's login store (lib/auth_store.py agy).
set -uo pipefail
WRITE=0; MODEL="${AGY_DELEGATE_MODEL:-}"; TIMEOUT="${AGY_DELEGATE_TIMEOUT:-900}"; PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE=1 ;;
    --model) MODEL="$2"; shift ;;
    --timeout) TIMEOUT="$2"; shift ;;
    --file) PROMPT="$(cat "$2")"; shift ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    *) PROMPT="${PROMPT:+$PROMPT }$1" ;;
  esac
  shift
done
[ -n "$PROMPT" ] || { echo "No task given." >&2; exit 2; }

export PATH="$HOME/.local/bin:$PATH"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
AUTH=("$PY" "$KIT/lib/auth_store.py" agy)
CLOUD=0; [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && CLOUD=1
TOKEN="${AGY_AUTH_DIR:-$HOME/.gemini/antigravity-cli}/antigravity-oauth-token"
command -v agy >/dev/null 2>&1 || { echo "agy not found. Run: bash $KIT/install.sh agy" >&2; exit 3; }
if [ ! -s "$TOKEN" ]; then
  [ "$CLOUD" = 1 ] && (cd "$ROOT" && "${AUTH[@]}" restore) >&2
  [ -s "$TOKEN" ] || { echo "agy is not logged in. Run: python3 $KIT/agy/login_headless.py start" >&2; exit 4; }
fi

RULES="You are working as a helper for another agent who will review your work.
Do not run git commit, git push, or delete files. Finish with a short summary:
what you changed (file paths) and anything you were unsure about.
When you report facts from the web: give the source URL and a short verbatim quote
for each; if you cannot verify a quote or a date, write \"no source\" or \"unverified\"
instead of guessing. Never invent quotes."
[ "$WRITE" = 0 ] && RULES="$RULES
This is a read-only task: do not create or edit files; answer in text."
ARGS=()
if [ "$WRITE" = 1 ]; then ARGS+=(--mode accept-edits); else ARGS+=(--mode plan); fi
[ -n "$MODEL" ] && ARGS+=(--model "$MODEL")
TIMEOUT_CMD=(); command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD=(timeout "$TIMEOUT")
LOG_DIR="$ROOT/.agy-runs"; mkdir -p "$LOG_DIR"; LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
START=$(date +%s)
. "$KIT/lib/scrub_env.sh"; scrub_env_prefix agy   # keep secrets the helper does not need out of its environment

# The prompt must be attached to --print (--print=...), or agy takes the next flag as the prompt.
(cd "$ROOT" && ${SCRUB[@]+"${SCRUB[@]}"} ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} agy "${ARGS[@]}" --print="$RULES

Task:
$PROMPT") 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
# Count this run for the usage summary (best effort; see lib/usage_log.py).
OUT_CHARS=$(wc -c < "$LOG" 2>/dev/null || echo 0)
AI_KIT_PROJECT="$ROOT" python3 "$KIT/lib/usage_log.py" add agy "$STATUS" "$(( $(date +%s) - START ))" "$WRITE" "${MODEL:-}" "${#PROMPT}" "${OUT_CHARS//[[:space:]]/}" >&2 || true
echo
echo "==> agy exit=$STATUS log=$LOG"
[ "$STATUS" = 124 ] && echo "==> timed out after ${TIMEOUT}s"
echo "==> changed files:"
git -C "$ROOT" status --short 2>/dev/null | grep -vE '\.(agy|codex|cursor)-runs/' || true
[ "$CLOUD" = 1 ] && (cd "$ROOT" && "${AUTH[@]}" save) 2>&1 | sed 's/^/==> /'
exit "$STATUS"
