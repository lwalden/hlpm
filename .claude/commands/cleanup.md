# /cleanup — Remove finished dispatch artifacts from consumer repos

Archive and remove `.exec/` dispatch state from repos whose dispatch has reached
a terminal state (`done`, `cancelled`, or `error`), so the tracking files stop
lingering as uncommitted local artifacts in the worked-in repo. The audit trail
is preserved out-of-tree before removal.

`/status` already does this automatically for repos it reports as finished — use
`/cleanup` for an on-demand sweep, or to clean a specific repo.

---

## Input

Optional repo names: $ARGUMENTS. If none are given, clean every repo with a
terminal-status dispatch.

Determine `SOURCE_ROOT`: use the `SOURCE_ROOT` env var if set; otherwise infer as
the parent directory of this HLPM repo.

Determine `ARCHIVE_ROOT`: use the `HLPM_EXEC_ARCHIVE` env var if set; otherwise
`{HLPM repo root}/.dispatch-archive` (gitignored — a local, portfolio-wide audit
store).

## Process

### 1. Determine target repos

- If `$ARGUMENTS` names repos, use those.
- Otherwise read `PROJECT-INDEX.md` (like `/status`) and check each Active,
  Paused, and recently-Mothballed repo for a `{SOURCE_ROOT}/{repo}/.exec/` dir.

### 2. Clean each target

For each target repo, run the shared cleanup script (it lives in this HLPM repo
and operates on the consumer repo by absolute path):

```bash
bash {HLPM repo root}/.claude/scripts/exec-cleanup.sh "{SOURCE_ROOT}/{repo}" "{ARCHIVE_ROOT}"
```

The script is safe by design:
- It **refuses** to clean a repo whose status is `running`, `blocked`, or
  `starting` (never wipe an in-flight dispatch) and exits with code `2`.
- Append `--force` **only** if the user explicitly asked to force-clean an
  active dispatch.
- It exits `0` and does nothing if there is no `.exec/` to clean.

### 3. Report

```
Cleaned {N} dispatch(es):

| Repo | Status | Archived to |
|---|---|---|
| my-repo | done | .dispatch-archive/my-repo/20260621T180000Z-2026-06-21-003 |

Skipped (active dispatch — not cleaned): {repos with running/blocked/starting status, or "none"}
```

If nothing was eligible, say "No finished dispatches to clean."

## Notes

- The full `.exec/` payload (directive + final status + append-only history) is
  copied to `{ARCHIVE_ROOT}/{repo}/{timestamp}-{directive_id}/` before removal, so
  the audit trail survives outside the consumer repo's working tree.
- This only touches `.exec/` (dispatch state). It never touches sprint files,
  application code, or git history.
- Safe to run anytime — non-terminal dispatches are skipped unless forced.
