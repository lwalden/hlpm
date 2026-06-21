#!/bin/bash
# exec-cleanup.sh — Archive and remove a consumer repo's .exec/ dispatch artifacts.
#
# Runs from the executive layer (HLPM), operating on a dispatched consumer repo
# by absolute path. Archives the repo's .exec/ directory (directive + final
# status + append-only history) to a timestamped, out-of-tree location, then
# removes .exec/ from the consumer repo's working tree so the dispatch tracking
# files stop lingering as uncommitted local artifacts.
#
# Usage:
#   bash exec-cleanup.sh <repo_path> <archive_root> [--force]
#
#   <repo_path>     Absolute path to the consumer repo (the one containing .exec/).
#   <archive_root>  Absolute path under which the archive is created. The archive
#                   lands at <archive_root>/<repo_name>/<timestamp>-<directive_id>/.
#   --force         Clean even if the dispatch status is not terminal. Without it,
#                   the script REFUSES to touch a running, blocked, or starting
#                   dispatch (never wipe the state of an in-flight dispatch).
#
# Safety: by default only cleans dispatches in a terminal state
# (done | cancelled | error).
#
# Exit codes:
#   0  cleaned, or nothing to do (no .exec/)
#   2  refused — status is non-terminal and --force was not given
#   3  usage error

REPO_PATH="$1"
ARCHIVE_ROOT="$2"
FORCE=0
[ "$3" = "--force" ] && FORCE=1

if [ -z "$REPO_PATH" ] || [ -z "$ARCHIVE_ROOT" ]; then
  echo "usage: exec-cleanup.sh <repo_path> <archive_root> [--force]" >&2
  exit 3
fi

EXEC_DIR="$REPO_PATH/.exec"
STATUS_FILE="$EXEC_DIR/status.md"

# Nothing to clean.
if [ ! -d "$EXEC_DIR" ]; then
  echo "no .exec/ in $REPO_PATH — nothing to clean"
  exit 0
fi

# Read terminal status from the status file (if any).
status=""
directive_id=""
if [ -f "$STATUS_FILE" ]; then
  status=$(sed -n 's/^status: *//p' "$STATUS_FILE" | head -1 | tr -d '\r')
  directive_id=$(sed -n 's/^directive_id: *//p' "$STATUS_FILE" | head -1 | tr -d '\r')
fi

case "$status" in
  done|cancelled|error)
    : # terminal — safe to clean
    ;;
  *)
    if [ "$FORCE" -ne 1 ]; then
      echo "refusing to clean $REPO_PATH — status is '${status:-unknown}' (not terminal). Pass --force to override." >&2
      exit 2
    fi
    ;;
esac

repo_name=$(basename "$REPO_PATH")
timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
dest="$ARCHIVE_ROOT/$repo_name/${timestamp}${directive_id:+-$directive_id}"

mkdir -p "$dest"
# Copy the whole .exec/ payload (directive, final status, history) to the archive.
cp -a "$EXEC_DIR/." "$dest/" 2>/dev/null

rm -rf "$EXEC_DIR"

echo "cleaned $repo_name (status: ${status:-unknown}) — archived to $dest"
