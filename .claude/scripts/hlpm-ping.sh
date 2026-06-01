#!/usr/bin/env bash
# ADR-006 HLPM ping -- writes a session-boundary event to the HLPM
# event log so HLPM's SessionStart summarizer can report "what happened
# while you were away" grouped by consumer repo.
#
# Called by SessionStart (startup matcher) and SessionEnd hooks with the
# event name as $1 (session_start | session_end).
#
# Silent fail in three cases:
#   - HLPM not present on this machine (cross-machine safe)
#   - HLPM_PING_DISABLED=1 environment variable set (per-session opt-out)
#   - Running inside HLPM itself (HLPM uses its own hlpm-log-session-end.sh)
set -euo pipefail
trap 'exit 0' ERR

EVENT="${1:-}"
[[ -n "$EVENT" ]] || exit 0

[[ "${HLPM_PING_DISABLED:-0}" == "1" ]] && exit 0

# Set HLPM_DIR to your HLPM repo path (or export it from your shell profile).
# Auto-detects via a sibling-directory convention if unset.
HLPM_DIR="${HLPM_DIR:-}"
if [[ -z "$HLPM_DIR" ]]; then
  # Convention: look for a repo named "hlpm" next to the consumer repo's parent
  _CONSUMER_PARENT="$(dirname "$(git rev-parse --show-toplevel 2>/dev/null || echo "")" 2>/dev/null || true)"
  _CANDIDATE="$_CONSUMER_PARENT/hlpm"
  [[ -d "$_CANDIDATE" ]] && HLPM_DIR="$_CANDIDATE"
fi
LOG_FILE="$HLPM_DIR/events.jsonl"
MAX_LINES=10000

[[ -d "$HLPM_DIR" ]] || exit 0

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
REPO=$(basename "$REPO_ROOT")

# Skip if running inside HLPM itself (HLPM uses its own hlpm-log-session-end.sh).
HLPM_NAME=$(basename "$HLPM_DIR")
[[ "$REPO" == "$HLPM_NAME" ]] && exit 0

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
EVENT_JSON=$(printf '{"ts":"%s","repo":"%s","event":"%s","branch":"%s"}' "$TS" "$REPO" "$EVENT" "$BRANCH")

# Inline trim-on-append (mirrors hlpm-log-append.sh in HLPM).
if [[ -f "$LOG_FILE" ]]; then
  CURRENT=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  if [[ "$CURRENT" -ge "$MAX_LINES" ]]; then
    KEEP=$((MAX_LINES - 1))
    tail -n "$KEEP" "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
fi

printf '%s\n' "$EVENT_JSON" >> "$LOG_FILE"
exit 0
