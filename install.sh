#!/bin/bash
# Install the helper CLIs in a fresh (cloud) environment.
#   bash install.sh            # all three
#   bash install.sh codex agy
# Best-effort: a tool that fails to install prints a warning, but the script
# still exits 0 so it never blocks a cloud environment's setup step.
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
mkdir -p "$HOME/.local/bin" 2>/dev/null

WANT=("$@"); [ ${#WANT[@]} -gt 0 ] || WANT=(codex cursor agy)

warn() { echo "warn: $*" >&2; }

# retry <cmd...>: up to 3 attempts for flaky network/proxy failures
retry() {
  local n
  for n in 1 2 3; do "$@" && return 0; sleep $((n * 2)); done
  return 1
}

install_codex() {
  command -v npm >/dev/null 2>&1 || { warn "npm not found; skipping codex"; return 1; }
  # global install needs write access; fall back to a user-level prefix
  if retry npm install -g @openai/codex; then return 0; fi
  warn "npm -g failed; retrying with prefix ~/.npm-global"
  retry npm install -g --prefix "$HOME/.npm-global" @openai/codex
}

# fetch_and_run <url>: download first so a failed download isn't piped into bash
fetch_and_run() {
  local f; f=$(mktemp) || return 1
  retry curl -fsSL --max-time 60 "$1" -o "$f" && bash "$f"
  local rc=$?; rm -f "$f"; return $rc
}

for t in "${WANT[@]}"; do
  case "$t" in
    codex)  command -v codex >/dev/null 2>&1 || install_codex || warn "codex install failed" ;;
    agy)    command -v agy >/dev/null 2>&1 || fetch_and_run https://antigravity.google/cli/install.sh || warn "agy install failed" ;;
    cursor) command -v agent >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1 || fetch_and_run https://cursor.com/install || warn "cursor install failed" ;;
    *) echo "unknown tool: $t" >&2; exit 2 ;;
  esac
done

echo "kit: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for c in codex agy agent cursor-agent; do command -v "$c" >/dev/null 2>&1 && echo "ok: $c"; done
if [ -n "${CURSOR_API_KEY:-}" ]; then echo "ok: CURSOR_API_KEY is set"; else echo "note: CURSOR_API_KEY is not set"; fi
exit 0
