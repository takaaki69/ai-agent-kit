#!/bin/bash
# Hand one task to the Cursor CLI (`agent -p`, Takaaki's Cursor plan).
#
#   bash cursor/delegate.sh [--write] [--model NAME] [--timeout SEC] "task"
#   bash cursor/delegate.sh [--write] --file prompt.md
#
# Without --write the agent runs in ask mode (read-only). Ask mode still needs
# --force, or the CLI denies web search (it cannot prompt for approval in -p mode);
# ask mode itself keeps file edits and shell commands blocked. Auth: CURSOR_API_KEY in
# the environment (cloud; no login step) or an existing `agent login` (Mac).
# Install the CLI with install.sh; in a cloud session a missing CLI is installed here.
set -uo pipefail
WRITE=0; MODEL="${CURSOR_DELEGATE_MODEL:-}"; TIMEOUT="${CURSOR_DELEGATE_TIMEOUT:-900}"; PROMPT=""
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
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The installer puts `agent` in ~/.local/bin; search it even when the shell does not.
export PATH="$HOME/.local/bin:$PATH"
CLI="$(command -v agent || command -v cursor-agent || true)"
if [ -z "$CLI" ] && [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  # Cloud session where setup did not install it (network hiccup, hook skipped): install now.
  echo "==> Cursor CLI not found; installing" >&2
  bash "$KIT/install.sh" cursor >&2 || true
  CLI="$(command -v agent || command -v cursor-agent || true)"
fi
[ -n "$CLI" ] || { echo "Cursor CLI not found. Run: bash $KIT/install.sh cursor (needs cursor.com and *.cursor.sh on the network allow list)" >&2; exit 3; }
if [ -z "${CURSOR_API_KEY:-}" ] && [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  echo "CURSOR_API_KEY is not set (add it to the cloud environment's variables)." >&2; exit 4
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RULES="You are working as a helper for another agent who will review your work.
Do not run git commit, git push, or delete files. Do not call paid generation
APIs (image, video, voice) unless the task says so. Finish with a short summary:
what you changed (file paths) and anything you were unsure about."
ARGS=(-p --trust --output-format text --workspace "$ROOT")
# --force auto-approves tool calls (web search included); ask mode keeps it read-only.
ARGS+=(--force)
[ "$WRITE" = 1 ] || ARGS+=(--mode ask)
[ -n "$MODEL" ] && ARGS+=(--model "$MODEL")
# macOS has no `timeout`; use gtimeout if present, otherwise run without a limit.
TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD=(timeout "$TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD=(gtimeout "$TIMEOUT")
fi
LOG_DIR="$ROOT/.cursor-runs"; mkdir -p "$LOG_DIR"; LOG="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"
{ echo "# $(date -Iseconds) write=$WRITE model=${MODEL:-default} timeout=${TIMEOUT}s"; echo "# task: $PROMPT"; echo; } > "$LOG"

${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} "$CLI" "${ARGS[@]}" "$RULES

Task:
$PROMPT" 2>&1 | tee -a "$LOG"
STATUS=${PIPESTATUS[0]}
echo
echo "==> cursor exit=$STATUS log=$LOG"
[ "$STATUS" = 124 ] && echo "==> timed out after ${TIMEOUT}s"
echo "==> changed files:"
git -C "$ROOT" status --short 2>/dev/null | grep -v '.cursor-runs/' || true
exit "$STATUS"
