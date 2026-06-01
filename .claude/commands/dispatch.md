# /dispatch — Dispatch work to one or more repos

Dispatch autonomous work sessions to consumer repos. The user provides a natural-language description of what work should happen in which repos. You parse it, write directives, and spawn background Claude sessions.

---

## Input

The user will say something like:
- "dispatch to my-repo: work the next 3 sprint items"
- "dispatch to my-repo and my-other-repo: my-repo do S39-003 through S39-005, my-other-repo review PR #65"
- "dispatch to my-repo: add these 4 items to the backlog: [list]"

Parse the repo names and scope descriptions from the user's message. $ARGUMENTS contains the raw input.

Determine SOURCE_ROOT: use `$env:SOURCE_ROOT` env var if set; otherwise infer as the parent directory of this HLPM repo (the directory containing the `hlpm` folder).

## Process (per repo)

For each repo mentioned:

### 1. Validate

- Confirm `{SOURCE_ROOT}/{repo}` exists
- Check if `.exec/status.md` already exists in that repo:
  - If `status: running` and `last_updated` is within 15 minutes: **refuse**. Tell the user there's an active dispatch. They must `/cancel` first.
  - If `status: blocked`: **refuse**. Tell the user there's a blocked dispatch awaiting `/resume`.
  - If `status: done`, `error`, `cancelled`, or stale (>15 min): proceed (overwrite old state)

### 2. Generate directive

Create a unique directive ID: `{YYYY-MM-DD}-{NNN}` where NNN increments per day.

Write `{SOURCE_ROOT}/{repo}/.exec/directive.md`:

```markdown
---
schema_version: 1
directive_id: {id}
dispatched_at: {ISO 8601 with timezone}
dispatched_to: {repo name}
mode: full-autonomy
permissions:
  commits: allow
  prs_open: allow
  prs_merge: allow-on-quality-gate-pass
  install_deps: allow-if-needed-for-scope
  external_api_spend: deny
  out_of_scope_changes: deny
report_cadence: every-phase-transition
---

# Scope

{the scope text from the user's message for this repo}

# Constraints

{any constraints the user mentioned, or "None specified."}
```

### 3. Write starting status stub

Write `{SOURCE_ROOT}/{repo}/.exec/status.md`:

```markdown
---
schema_version: 1
status: starting
directive_id: {id}
started_at: {ISO 8601}
last_updated: {ISO 8601}
current_phase: INIT
current_item: n/a
context_remaining_pct: 100
heartbeat_ttl_minutes: 15
---

# Summary

Dispatch starting. Agent has not yet begun execution.
```

### 4. Append to history

Run `bash -c 'cd "{SOURCE_ROOT}/{repo}" && bash .claude/scripts/exec-history-append.sh "directive dispatched (id {id})"'`

### 5. Spawn background agent

```bash
cd "{SOURCE_ROOT}/{repo}" && claude -p "DISPATCH MODE: You are running in dispatch mode. Read .exec/directive.md and execute the directive autonomously following the sprint-master Dispatch Mode protocol in .claude/agents/sprint-master.md. Write status to .exec/status.md at each phase transition. Exit cleanly on completion or blocker." --agent sprint-master --permission-mode bypassPermissions
```

Run this with `run_in_background: true`. Do NOT wait for it to complete.

### 6. Report

After spawning all repos, report to the user:

```
Dispatched {N} repos:

| Repo | Directive ID | Scope |
|---|---|---|
| {repo1} | {id1} | {scope summary, 1 line} |
| {repo2} | {id2} | {scope summary, 1 line} |

Use /status to check progress. Use /cancel {repo} to abort. Use /resume {repo} after clearing blockers.
```

## Notes

- Create `.exec/` directory in target repo if it doesn't exist (`mkdir -p`)
- All dispatches are parallel — spawn all backgrounds before reporting
- If a repo doesn't have AAM installed, warn the user and skip. AAM is installed if **either** `.claude/agents/sprint-master.md` exists (v4, vendored) **or** `.claude/aiagentminder-version` exists (v5+, plugin model — sprint-master is a global agent, not a local file)
- If the user specifies custom permissions or constraints, incorporate them into the directive
