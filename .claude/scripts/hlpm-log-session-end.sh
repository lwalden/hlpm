#!/usr/bin/env bash
# ADR-006 HLPM SessionEnd hook -- writes hlpm_session_end marker to
# events.jsonl so the summarizer knows where "since last session" starts.
set -euo pipefail
trap 'exit 0' ERR

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
EVENT=$(printf '{"ts":"%s","repo":"highest-level-project-management","event":"hlpm_session_end","branch":"%s"}' "$TS" "$BRANCH")

bash "$(dirname "$0")/hlpm-log-append.sh" "$EVENT"
exit 0
