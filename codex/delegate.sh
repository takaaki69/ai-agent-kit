#!/bin/bash
# Hand one task to the Codex CLI (`codex exec`, the user's ChatGPT plan) and save its output.
#
#   bash scripts/codex/delegate.sh [--write] [--model NAME] [--effort low|medium|high] [--timeout SEC] "task"
#   bash scripts/codex/delegate.sh [--write] --file prompt.md
#
# Without --write, Codex runs in a read-only sandbox and only answers. With
# --write it may edit files in this checkout (no commits, no pushes; the caller
# reviews the diff). Auth: the ChatGPT login in ~/.codex/auth.json. In the cloud
# it comes from the kit's login store (lib/auth_store.py); a refreshed login goes back.
set -uo pipefail

WRITE=0
MODEL="${CODEX_DELEGATE_MODEL:-}"
EFFORT="${CODEX_DELEGATE_EFFORT:-}"
TIMEOUT="${CODEX_DELEGATE_TIMEOUT:-900}"
PROMPT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --write) WRITE=1 ;;
    --model) MODEL="$2"; shift ;;
    --effort) EFFORT="$2"; shift ;;
    --timeout) TIMEOUT="$2"; shift ;;
    --file) PROMPT="$(cat "$2")"; shift ;;
    -h|--help) sed -n 2,10p "$0"; exit 0 ;;
    *) PROMPT="${PROMPT:+$PROMPT }$1" ;;
  esac
  shift
done
[ -n "$PROMPT" ] || { echo "No task given." >&2; exit 2; }

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
AUTH=("$PY" "$KIT/lib/auth_store.py" codex)
CLOUD=0; [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && CLOUD=1

if ! command -v codex >/dev/null 2>&1; then
  echo "Codex CLI not found. Install: npm install -g @openai/codex" >&2
  exit 3
fi
if ! codex login status >/dev/null 2>&1; then
  [ "$CLOUD" = 1 ] && (cd "$ROOT" && "${AUTH[@]}" restore) >&2
  if ! codex login status >/dev/null 2>&1; then
    echo "Codex is not logged in. Run: bash "$KIT/codex/login.sh"." >&2
    exit 4
  fi
fi
# macOS has no `timeout`; use gtimeout if present, otherwise run without a limit.
TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then TIMEOUT_CMD=(timeout "$TIMEOUT")
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT_CMD=(gtimeout "$TIMEOUT")
fi

LOG_DIR="$ROOT/.codex-runs"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$LOG_DIR/$STAMP.log"
ANSWER="$LOG_DIR/$STAMP.answer.md"

RULES="You are working as a helper for another agent who will review your work.
Do not run git commit, git push, or delete files. Do not call paid generation
APIs (image, video, voice) unless the task says so. Finish with a short summary:
what you changed (file paths) and anything you were unsure about."
if [ "$WRITE" = 0 ]; then
  RULES="$RULES
This is a read-only task: do not create or edit files; answer in text."
fi

ARGS=(exec --skip-git-repo-check -C "$ROOT" -o "$ANSWER" --color never)
if [ "$WRITE" = 1 ]; then ARGS+=(-s workspace-write); else ARGS+=(-s read-only); fi
[ -n "$MODEL" ] && ARGS+=(-m "$MODEL")
[ -n "$EFFORT" ] && ARGS+=(-c "model_reasoning_effort=\"$EFFORT\"")

{
  echo "# $(date -Iseconds) write=$WRITE model=${MODEL:-default} effort=${EFFORT:-default} timeout=${TIMEOUT}s"
  echo "# task: $PROMPT"
  echo
} > "$LOG"
START=$(date +%s)

# The prompt goes through stdin so long tasks need no quoting.
printf '%s\n\nTask:\n%s\n' "$RULES" "$PROMPT" \
  | ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} codex "${ARGS[@]}" - >>"$LOG" 2>&1
STATUS=$?
# Count this run for the usage summary (best effort; see lib/usage_log.py).
OUT_CHARS=$(wc -c < "${ANSWER:-$LOG}" 2>/dev/null || echo 0)
AI_KIT_PROJECT="$ROOT" python3 "$KIT/lib/usage_log.py" add codex "$STATUS" "$(( $(date +%s) - START ))" "$WRITE" "${MODEL:-}" "${#PROMPT}" "${OUT_CHARS//[[:space:]]/}" >&2 || true

if [ -s "$ANSWER" ]; then cat "$ANSWER"; else tail -n 40 "$LOG"; fi
echo
echo "==> codex exit=$STATUS log=$LOG"
[ "$STATUS" = 124 ] && echo "==> timed out after ${TIMEOUT}s"
# Only a failed run counts, and only Codex's own closing error lines (not the task
# header or documents Codex read, which can mention "rate limit" in passing).
if [ "$STATUS" != 0 ] && tail -n +4 "$LOG" | tail -n 15 | grep -qiE 'usage limit|rate limit|hit your limit'; then
  echo "==> Codex plan limit reached (see the log)"
fi
echo "==> changed files:"
git -C "$ROOT" status --short 2>/dev/null | grep -v '.codex-runs/' || true

# Codex may have refreshed the login; keep Drive's copy current.
[ "$CLOUD" = 1 ] && (cd "$ROOT" && "${AUTH[@]}" save) 2>&1 | sed 's/^/==> /'
exit "$STATUS"
