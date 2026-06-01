#!/usr/bin/env bash
# ADR-006 event log helper -- append a JSON event to events.jsonl with
# inline trim-on-append (cap 10,000 lines). Silent fail on any error.
#
# Usage: hlpm-log-append.sh '<single-line JSON event>'
set -euo pipefail
trap 'exit 0' ERR

EVENT_JSON="${1:-}"
[[ -n "$EVENT_JSON" ]] || exit 0

LOG_DIR="D:/Source/highest-level-project-management"
LOG_FILE="$LOG_DIR/events.jsonl"
MAX_LINES=10000

[[ -d "$LOG_DIR" ]] || exit 0

if [[ -f "$LOG_FILE" ]]; then
  CURRENT=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
  if [[ "$CURRENT" -ge "$MAX_LINES" ]]; then
    KEEP=$((MAX_LINES - 1))
    tail -n "$KEEP" "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
fi

printf '%s\n' "$EVENT_JSON" >> "$LOG_FILE"
exit 0
