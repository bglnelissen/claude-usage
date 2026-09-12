#!/bin/bash
# b. nelissen
# claude-usage.sh
#
# Reports Claude plan usage. Measures on its own, with `claude -p /usage`.
# See claude-usage.sh --help for the options.
# Not to be confused with ~/bin/claude-usage, the Python version from the
# claude-usage project. That one can also report the reset times; this cannot.

set -eo pipefail

show_help() {
  cat <<'HELP'
Usage: claude-usage.sh [--json|--text|--shellfish] [target]

Reads Claude plan usage with `claude -p /usage` and reports the current
session (the five hour window) and the week, both as percent used.

  --json       one line of JSON, with fetched_at (default)
  --text       one readable line
  --shellfish  push two bars to the Secure ShellFish widget
  -h, --help   this help

Target applies to --shellfish only, and defaults to "Mini Claude Usage".
HELP
}

# No flag means JSON. An unknown flag is an error, because otherwise it would
# silently be taken as the target name. Help comes before the measurement, so
# --help answers at once instead of waiting two seconds on claude.
MODE=json
case "${1:-}" in
  -h | --help) show_help; exit 0 ;;
  --json) MODE=json; shift ;;
  --text) MODE=text; shift ;;
  --shellfish) MODE=shellfish; shift ;;
  -*) echo "claude-usage.sh: unknown option: $1" >&2
      echo "try --help" >&2
      exit 2 ;;
esac

TARGET="${1:-Mini Claude Usage}"

# Where claude lives: own setting, then PATH, then the default location.
# Cron has a bare PATH without ~/.local/bin, so that third one is needed.
CLAUDE_BIN="${CLAUDE_BIN:-$(command -v claude || echo "$HOME/.local/bin/claude")}"

# .shellfishrc was not written against set -u, hence that stays off.
source "$HOME/.shellfishrc"

# `claude -p /usage` is a local command of Claude Code itself: it costs no
# tokens and does not count against the limits. The flags keep it clean: no
# session file per call, no MCP servers, and no hooks (those would fire a push
# notification on every measurement). An API key in the environment would spend
# credits instead of the subscription, so those two are dropped. stdin closed,
# because `claude -p` would otherwise sit waiting for input.
measurement=$(env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN \
  timeout 60 "$CLAUDE_BIN" -p /usage \
    --no-session-persistence \
    --strict-mcp-config \
    --settings '{"disableAllHooks": true}' </dev/null 2>&1) || {
  echo "claude-usage.sh: claude gave no usable answer: $measurement" >&2
  exit 1
}

session=$(grep -oP '^Current session:\s*\K[0-9]+' <<<"$measurement" || true)
week=$(grep -oP '^Current week[^:]*:\s*\K[0-9]+' <<<"$measurement" || true)

# Better to push nothing than a wrong number that stays on screen.
for value in "$session" "$week"; do
  case "$value" in
    '' | *[!0-9]*)
      echo "claude-usage.sh: no subscription data in the output:" >&2
      echo "$measurement" >&2
      exit 1
      ;;
  esac
done

# Green, orange from x, red from y.
color() {
  if [ "$1" -ge 90 ]; then
    echo "#ff3b30" # red
  elif [ "$1" -ge 70 ]; then
    echo "#ff9500" # orange
  else
    echo "#34c759"
  fi
}

# Output
output_text() {
  echo "Claude: session ${session}%, weekly ${week}%"
}

# Same keys as `claude-usage --json`, so a consumer only has to know one shape.
# %d keeps the numbers unquoted, otherwise Home Assistant cannot do arithmetic
# on them, and printf complains if text shows up where a number was expected.
output_json() {
  printf '{"current":%d,"weekly":%d,"fetched_at":"%s"}\n' \
    "$session" "$week" "$(date -Iseconds)"
}

output_shellfish() {
  widget --target "$TARGET" \
    "Claude ${session}%" \
    --color "$(color "$session")" \
    --text '\n' --icon clock \
    --progress "${session}%" \
    --color "$(color "$week")" \
    --text '\n' --icon calendar \
    --progress "${week}%"
}

case "$MODE" in
  json) output_json ;;
  text) output_text ;;
  shellfish) output_shellfish ;;
esac
