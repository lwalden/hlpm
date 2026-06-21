# /status — Aggregated dispatch status across all repos

Read `.exec/status.md` from every repo that has one and present a unified view. Surfaces blockers, stalled agents, and completed work.

---

## Input

No arguments required. Optionally the user can name specific repos to check: $ARGUMENTS

## Process

### 1. Scan all active repos

Read `PROJECT-INDEX.md` and extract all Active, Paused, and recently-Mothballed repo folder names. These are the repos to check.

Determine `SOURCE_ROOT`:
- Read the `SOURCE_ROOT` env var if set (`$env:SOURCE_ROOT` on PowerShell / `$SOURCE_ROOT` in bash)
- Otherwise infer: the parent directory of the HLPM repo (this repo). E.g. if HLPM is at `/path/to/source/hlpm`, SOURCE_ROOT is `/path/to/source`.

Check if `{SOURCE_ROOT}/{repo}/.exec/status.md` exists. If yes, read it.

### 2. Parse each status file

Extract from YAML frontmatter:
- `status` (starting/running/blocked/done/error/cancelled)
- `directive_id`
- `last_updated`
- `current_phase`
- `current_item`
- `context_remaining_pct`
- `heartbeat_ttl_minutes` (default 15)

Extract from body:
- `# Summary` section (first line after the heading)
- `# Blocked` section (if status is blocked — include the full blocker context)

### 3. Compute staleness

For each repo with `status: running`:
- Parse `last_updated` as a timestamp
- If older than `heartbeat_ttl_minutes` (default 15 minutes): mark as **STALLED**

### 4. Present unified view

```
## Dispatch Status ({timestamp})

| Repo | Status | Phase | Item | Last Update | Summary |
|---|---|---|---|---|---|
| accessi-shield | 🟢 running | EXECUTE | S39-004 | 3 min ago | 2/3 items done |
| n8n-hub | 🟡 blocked | EXECUTE | S6-002 | 22 min ago | Needs Cloudflare decision |
| localrigsidea | ✅ done | COMPLETE | — | 1 hr ago | All 4 backlog items added |
| TradingSystem | ⚪ no dispatch | — | — | — | — |

### Needs attention

🟡 **n8n-hub** — BLOCKED
{full content of the # Blocked section from n8n-hub's status file}

🔴 **accessi-shield** — STALLED (last update 22 min ago, TTL 15 min)
Agent may have crashed. Use /cancel accessi-shield and re-dispatch, or investigate.
```

### Status icons
- 🟢 `running` (heartbeat fresh)
- 🟡 `blocked` (needs human action)
- 🔴 `running` but STALLED (heartbeat expired)
- ✅ `done`
- ❌ `error`
- ⚪ `cancelled` or no dispatch
- 🔵 `starting` (agent spawned but hasn't reported yet)

### 5. Recommendations

After the table, note actionable next steps:
- For blocked repos: "Use `/resume {repo}` with the resolution to unblock"
- For stalled repos: "Use `/cancel {repo}` and re-dispatch, or check the process manually"
- For done repos: noted as completed and auto-cleaned in step 6 below (or run `/cleanup {repo}` manually)

### 6. Auto-clean finished dispatches

After presenting the view, archive and remove the `.exec/` state of every repo
you just reported in a terminal state (`done`, `cancelled`, or `error`) so the
tracking files stop lingering as uncommitted local artifacts in the worked-in
repo. Do this in the same run that surfaces the final status, so the user always
sees the result alongside the cleanup notice.

Determine `ARCHIVE_ROOT`: use the `HLPM_EXEC_ARCHIVE` env var if set; otherwise
`{HLPM repo root}/.dispatch-archive` (gitignored — local audit store).

For each terminal-status repo, run the shared cleanup script:

```bash
bash {HLPM repo root}/.claude/scripts/exec-cleanup.sh "{SOURCE_ROOT}/{repo}" "{ARCHIVE_ROOT}"
```

**NEVER** auto-clean a repo whose status is `running`, `blocked`, or `starting` —
the script refuses these by default; do not pass `--force` here.

Then append one line to the report (omit it if nothing was terminal):

```
Cleaned up finished dispatch(es): {repos}. Audit trail archived under {ARCHIVE_ROOT}.
```

The full `.exec/` payload (directive + final status + append-only history) is
copied to `{ARCHIVE_ROOT}/{repo}/{timestamp}-{directive_id}/` before removal, so
the audit trail survives outside the consumer repo's working tree.

## Notes

- If no repos have `.exec/status.md`, say "No active dispatches."
- Read files using the Read tool, not bash cat — handles paths with spaces correctly
- This command is also called automatically at session start (per git-strategy rule)
