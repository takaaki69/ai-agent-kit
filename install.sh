#!/bin/bash
# Install the helper CLIs in a fresh (cloud) environment.
#   bash install.sh            # all three
#   bash install.sh codex gemini
set -uo pipefail
WANT=("$@"); [ ${#WANT[@]} -gt 0 ] || WANT=(codex cursor gemini)
for t in "${WANT[@]}"; do
  case "$t" in
    codex)  command -v codex  >/dev/null 2>&1 || npm install -g @openai/codex ;;
    gemini) command -v gemini >/dev/null 2>&1 || npm install -g @google/gemini-cli ;;
    cursor) command -v agent  >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1 || curl -fsS https://cursor.com/install | bash ;;
    *) echo "unknown tool: $t" >&2; exit 2 ;;
  esac
done
echo "kit: $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for c in codex gemini agent cursor-agent; do command -v "$c" >/dev/null 2>&1 && echo "ok: $c"; done
[ -n "${CURSOR_API_KEY:-}" ] && echo "ok: CURSOR_API_KEY is set" || echo "note: CURSOR_API_KEY is not set"
