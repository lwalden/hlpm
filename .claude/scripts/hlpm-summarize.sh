#!/usr/bin/env bash
# ADR-006 HLPM SessionStart summarizer -- reads events.jsonl since the last
# hlpm_session_end marker, summarizes consumer-repo activity, and appends a
# drift-check report. Output is injected into Claude's SessionStart context.
set -euo pipefail
trap 'exit 0' ERR

# Read and discard hook input from stdin (not needed for decision-making).
cat > /dev/null

HLPM_DIR="${HLPM_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
LOG_FILE="$HLPM_DIR/events.jsonl"
SCRIPT_DIR="$(dirname "$0")"

HEADER=""
EVENTS=""

BOUNDARY_TS=""
if [[ -f "$LOG_FILE" ]]; then
  LAST_END_LINE=$(grep -n 'hlpm_session_end' "$LOG_FILE" 2>/dev/null | tail -1 | cut -d: -f1 || true)
  if [[ -z "${LAST_END_LINE:-}" ]]; then
    EVENTS=$(tail -n 20 "$LOG_FILE" 2>/dev/null || true)
    HEADER="No prior HLPM session on record. Recent 20 events:"
  else
    TOTAL=$(wc -l < "$LOG_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    # Timestamp of the last HLPM session marker = the read-time enrichment boundary.
    BOUNDARY_TS=$(sed -n "${LAST_END_LINE}p" "$LOG_FILE" 2>/dev/null | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' || true)
    if [[ "$LAST_END_LINE" -lt "$TOTAL" ]]; then
      EVENTS=$(tail -n +$((LAST_END_LINE + 1)) "$LOG_FILE" 2>/dev/null || true)
      HEADER="Consumer-repo activity since last HLPM session:"
    fi
  fi
fi

# Fall back to the earliest event in the window, then to a 14-day default.
if [[ -z "$BOUNDARY_TS" && -n "$EVENTS" ]]; then
  BOUNDARY_TS=$(printf '%s' "$EVENTS" | head -1 | sed -n 's/.*"ts":"\([^"]*\)".*/\1/p' || true)
fi
[[ -z "$BOUNDARY_TS" ]] && BOUNDARY_TS="14 days ago"

# Group events by repo, then enrich each active repo from its git state at READ
# TIME (ADR-007). Thin events tell us WHICH repos to inspect and the time
# boundary; git tells us WHAT changed. Every git call is guarded so one bad repo
# cannot abort the summary or block session start.
LINES=""
if [[ -n "$EVENTS" ]]; then
  SRC_ROOT="${SOURCE_ROOT:-$(dirname "$HLPM_DIR")}"
  declare -A REPO_EVENTS
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    REPO=$(printf '%s' "$line" | sed -n 's/.*"repo":"\([^"]*\)".*/\1/p')
    [[ -z "$REPO" ]] && continue
    REPO_EVENTS["$REPO"]=$(( ${REPO_EVENTS["$REPO"]:-0} + 1 ))
  done <<< "$EVENTS"

  for REPO in "${!REPO_EVENTS[@]}"; do
    SESSIONS="${REPO_EVENTS[$REPO]}"
    REPO_PATH="$SRC_ROOT/$REPO"

    # No git enrichment for HLPM itself or for a path that is not a repo on disk.
    HLPM_NAME=$(basename "$HLPM_DIR")
    if [[ "$REPO" == "$HLPM_NAME" || ! -d "$REPO_PATH/.git" ]]; then
      LINES+="  - ${REPO}: ${SESSIONS} session event(s)"$'\n'
      continue
    fi

    CC=$( { git -C "$REPO_PATH" log --oneline --since="$BOUNDARY_TS" 2>/dev/null || true; } | wc -l | tr -d ' ' )
    BR=$( git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?' )
    DEC=$( { git -C "$REPO_PATH" log --oneline --since="$BOUNDARY_TS" -- DECISIONS.md 2>/dev/null || true; } | wc -l | tr -d ' ' )

    HEAD_LINE="  - ${REPO}: ${SESSIONS} session event(s) · branch ${BR} · ${CC} commit(s) since last review"
    if [[ "${DEC:-0}" -gt 0 ]]; then
      HEAD_LINE="${HEAD_LINE} · DECISIONS.md changed (${DEC})"
    fi
    LINES+="${HEAD_LINE}"$'\n'

    if [[ "${CC:-0}" -gt 0 ]]; then
      SUBJ=$( { git -C "$REPO_PATH" log --since="$BOUNDARY_TS" --pretty=format:'%s' 2>/dev/null || true; } | head -3 )
      while IFS= read -r s; do
        [[ -z "$s" ]] && continue
        LINES+="      • ${s}"$'\n'
      done <<< "$SUBJ"
    fi
  done
fi

# Drift check runs independently.
DRIFT=$(bash "$SCRIPT_DIR/hlpm-drift-check.sh" 2>/dev/null || true)

# Tooling-findings inbox: written by AAM's hlpm-finding.sh during sprint
# retros in consumer repos. Never trimmed by writers — entries persist until
# /findings triage disposes them, so surface a pending count every session.
FINDINGS=""
FINDINGS_FILE="$HLPM_DIR/tooling-findings.jsonl"
if [[ -f "$FINDINGS_FILE" ]]; then
  FCOUNT=$(grep -c '"summary"' "$FINDINGS_FILE" 2>/dev/null || echo 0)
  if [[ "${FCOUNT:-0}" -gt 0 ]]; then
    FREPOS=$(sed -n 's/.*"repo":"\([^"]*\)".*/\1/p' "$FINDINGS_FILE" 2>/dev/null \
      | sort -u | paste -sd ',' - | sed 's/,/, /g')
    FINDINGS="${FCOUNT} untriaged AAM tooling finding(s) from: ${FREPOS:-unknown}. Run /findings to triage."
  fi
fi

# Build final context block.
CONTEXT=""
if [[ -n "$LINES" ]]; then
  CONTEXT="[HLPM summary] ${HEADER}"$'\n'"${LINES}"
fi
if [[ -n "$DRIFT" ]]; then
  [[ -n "$CONTEXT" ]] && CONTEXT="${CONTEXT}"$'\n'
  CONTEXT="${CONTEXT}[HLPM drift] ${DRIFT}"
fi
if [[ -n "$FINDINGS" ]]; then
  [[ -n "$CONTEXT" ]] && CONTEXT="${CONTEXT}"$'\n'
  CONTEXT="${CONTEXT}[HLPM findings] ${FINDINGS}"
fi

[[ -z "$CONTEXT" ]] && exit 0

# Escape for JSON (backslash, quote, tab, then real newlines to literal \n).
ESCAPED=$(printf '%s' "$CONTEXT" \
  | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' \
  | awk 'BEGIN{first=1} {if(!first) printf "\\n"; printf "%s", $0; first=0}')

printf '{"hookSpecificOutput":{"additionalContext":"%s"}}' "$ESCAPED"
exit 0
