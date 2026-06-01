#!/usr/bin/env bash
# ADR-006 drift detector -- diffs PROJECT-INDEX.md against reality.
#
# Two checks for v1:
#   - Folders listed in PROJECT-INDEX but missing under D:/Source
#   - Git repos under D:/Source not listed in PROJECT-INDEX
#
# Output: plain text, empty if no drift. Never edits PROJECT-INDEX.
set -euo pipefail
trap 'exit 0' ERR

HLPM_DIR="${HLPM_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
INDEX="$HLPM_DIR/PROJECT-INDEX.md"
SOURCE_ROOT="${SOURCE_ROOT:-$(dirname "$HLPM_DIR")}"

[[ -f "$INDEX" ]] || exit 0

# Extract folder slugs from [label](../folder/) markdown links.
LISTED=$(sed -n 's/.*\[[^]]*\](\.\.\/\([^/]*\)\/).*/\1/p' "$INDEX" | sort -u)

MISSING=""
for folder in $LISTED; do
  if [[ ! -d "$SOURCE_ROOT/$folder" ]]; then
    MISSING+="$folder"$'\n'
  fi
done

NOT_INDEXED=""
for dir in "$SOURCE_ROOT"/*/; do
  repo=$(basename "$dir")
  [[ -d "$dir/.git" ]] || continue
  if ! echo "$LISTED" | grep -ixq "$repo"; then
    NOT_INDEXED+="$repo"$'\n'
  fi
done

OUT=""
if [[ -n "$MISSING" ]]; then
  OUT+="  Missing (listed, not on disk):"$'\n'
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    OUT+="    - $line"$'\n'
  done <<< "$MISSING"
fi
if [[ -n "$NOT_INDEXED" ]]; then
  OUT+="  Not indexed (on disk, not in PROJECT-INDEX):"$'\n'
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    OUT+="    - $line"$'\n'
  done <<< "$NOT_INDEXED"
fi

if [[ -n "$OUT" ]]; then
  printf 'PROJECT-INDEX drift:\n%s' "$OUT"
fi
exit 0
