#!/bin/bash
# Source this, then call `scrub_env_prefix <tool>` (codex | cursor | agy).
# It sets SCRUB to a command prefix, `env -u NAME ...`, that removes secrets the helper does not
# need from the helper's environment (the kit's own steps, such as the login store, still see them).
# Removed: Drive credentials, ledger settings, Google service account keys, GitHub and Anthropic
# tokens, any variable whose name contains SECRET / REFRESH_TOKEN / PASSWORD / PRIVATE_KEY, and
# the other helpers' API keys. Add more names with AI_KIT_SCRUB_EXTRA="NAME1 NAME2".
# Turn it off with AI_KIT_SCRUB_ENV=0. Best effort: a miss only means a variable stays visible.
scrub_env_prefix() {
  SCRUB=()
  [ "${AI_KIT_SCRUB_ENV:-1}" = "0" ] && return 0
  local tool="$1" name
  local -a drop=(GOOGLE_SA_KEY_JSON GH_TOKEN GITHUB_TOKEN CLAUDE_CODE_OAUTH_TOKEN)
  case "$tool" in
    codex) drop+=(CURSOR_API_KEY) ;;
    cursor) drop+=(OPENAI_API_KEY CODEX_API_KEY) ;;
    agy) drop+=(CURSOR_API_KEY OPENAI_API_KEY CODEX_API_KEY) ;;
  esac
  # shellcheck disable=SC2206
  drop+=(${AI_KIT_SCRUB_EXTRA:-})
  while IFS= read -r name; do
    case "$name" in
      *_DRIVE_*|AI_KIT_LEDGER_*|ANTHROPIC_*|*SECRET*|*REFRESH_TOKEN*|*PASSWORD*|*PRIVATE_KEY*) drop+=("$name") ;;
    esac
  done < <(compgen -e)
  local -A seen=()
  for name in "${drop[@]}"; do
    [ -n "${!name+x}" ] && [ -z "${seen[$name]:-}" ] && { seen[$name]=1; SCRUB+=(-u "$name"); }
  done
  [ ${#SCRUB[@]} -gt 0 ] && SCRUB=(env "${SCRUB[@]}")
  return 0
}
