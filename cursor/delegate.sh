#!/bin/bash
# Hand one task to the Cursor CLI (`agent -p`, Takaaki's Cursor plan).
#
#   bash cursor/delegate.sh [--write] [--model NAME] [--timeout SEC] "task"
#   bash cursor/delegate.sh [--write] --file prompt.md
#
# Without --write the agent runs in ask mode (read-only). Auth: CURSOR_API_KEY in
# the environment (no login step). Install the CLI with install.sh.
set -uo pipefail
WRITE=0; MODEL="${CURSOR_DELEGATE_MODEL:-}"; TIMEOUT="${CURSOR_DELEGATE_TIMEOUT:-900}"; PROMPT=""
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
CLI="$(command -v agent || command -v cursor-agent || true)"
[ -n "$CLI" ] || { echo "Cursor CLI not found. Run: bash <kit>/install.sh cursor" >&2; exit 3; }
[ -n "${CURSOR_API_KEY:-}" ] || { echo "CURSOR_API_KEY is not set (add it to the environment's variables)." >&2; exit 4; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RULES="You are working as a helper for another agent who will review your work.
Do not run git commit, git push, or delete files. Finish with a short summary:
what you changed (file paths) and anything you were unsure about."
ARGS=(-p --trust --output-format text --workspace "$ROOT")
if [ "$WRITE" = 1 ]; then ARGS+=(--force); else ARGS+=(--mode ask); fi
[ -n "$MODEL" ] && ARGS+=(--model "$MODEL")
TIMEOUT_CMD=(); command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD=(timeout "$TIMEOUT")
LOG_DIR="$ROOT/.cursor-runs"; mkdir -p "$LOG_DIR"; LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"

${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$CLI" "${ARGS[@]}" "$RULES

Task:
$PROMPT" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
echo
echo "==> cursor exit=$STATUS log=$LOG"
[ "$STATUS" = 124 ] && echo "==> timed out after ${TIMEOUT}s"
echo "==> changed files:"
git -C "$ROOT" status --short 2>/dev/null | grep -v '.cursor-runs/' || true
exit "$STATUS"
