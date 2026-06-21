# Cross-Repo Dispatch Contract

> Locked: 2026-04-11
> Schema version: 1
> Status: design locked, implementation pending (Phase 1 + Phase 2 in PRIORITIES.md)

## Purpose

Defines the contract between the **executive layer** (this repo, where the user sits and directs work) and **per-repo Claude agents** (running inside individual consumer repos via AAM) so that:

1. The user can dispatch a scope of work to multiple repos in parallel from a single session in this repo.
2. The dispatched agents run autonomously without human prompting until they complete or hit a blocker.
3. The user can walk away for hours and come back to a unified status view.
4. Blockers surface with full context for human resolution.
5. Resume happens by updating the directive in place — the per-repo agent picks up where it left off.

This is the missing layer above AIAgentMinder. AAM handles execution within a single repo. The dispatch contract handles coordination across repos.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  highest-level-project-management  (executive layer)            │
│                                                                  │
│  • Read PRIORITIES.md / system-map.md / aggregated status       │
│  • Compose directive: "do X in repo A, Y in repo B, Z in C"     │
│  • Dispatch to per-repo agents (parallel)                       │
│  • Monitor status periodically                                  │
│  • Receive human-blocker reports from user, dispatch resumes    │
└────────────┬─────────────────────────┬──────────────────────────┘
             │ writes directives       │ reads status
             ▼                         ▲
   ┌──────────────────┐      ┌──────────────────┐
   │ .exec/directive  │      │ .exec/status     │
   │ .md (in repo A)  │      │ .md (in repo A)  │
   └────────┬─────────┘      └─────────▲────────┘
            │ read                     │ written
            ▼                          │
   ┌────────────────────────────────────┴─────────┐
   │  Per-repo Claude session  (in repo A)         │
   │  Spawned by dispatcher in --dispatch mode     │
   │                                                │
   │  • Reads directive, NOT human conversation    │
   │  • Runs AAM sprint-master orchestrator        │
   │  • Phase agents handle execution              │
   │  • On blocker: write status, exit cleanly     │
   │  • On done: write status, exit cleanly        │
   │  • Never prompts for anything in scope        │
   └────────────────────────────────────────────────┘
```

## File locations

Both files live at `.exec/` in the consumer repo root, NOT in `.claude/`. Rationale: `.claude/` is AAM-managed; `.exec/` is dispatch-managed. Separation of concerns.

`.exec/` is gitignored portfolio-wide via the AAM gitignore template (to be added in Phase 0 cleanup). Independently of that, the executive layer archives and removes `.exec/` once a dispatch reaches a terminal state — see [Cleanup](#cleanup-end-of-lifecycle) — so the tracking files do not linger as working-tree artifacts even in repos whose gitignore has not yet been updated.

| File | Purpose |
|---|---|
| `.exec/directive.md` | Latest directive (executive → repo). Rewritten in place on resume. |
| `.exec/status.md` | Latest status (repo → executive). Updated on phase transitions and at exit. |
| `.exec/history.md` | Append-only audit log of every directive version + status snapshot. |

## File format: directive

```markdown
---
schema_version: 1
directive_id: 2026-04-11-001
dispatched_at: 2026-04-11T17:30:00-07:00
dispatched_to: accessi-shield
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

Free-form description of what needs to happen. May reference SPRINT.md issues,
BACKLOG.md items, PR numbers, or describe new work.

# Constraints

Anything out of scope, hard limits, things to avoid.

# Resume Context (only present on resume)

Set when the executive rewrites this directive after a blocker is cleared.
Per-repo agent reads this to know how to continue.
```

### Directive frontmatter fields

| Field | Required | Values | Notes |
|---|---|---|---|
| `schema_version` | yes | integer (currently `1`) | For forward-compat; agents that don't recognize the version refuse to run and write status with `error: schema_version_mismatch` |
| `directive_id` | yes | `YYYY-MM-DD-NNN` | Used in history log; must be unique per repo |
| `dispatched_at` | yes | ISO 8601 with timezone | When the executive layer wrote this directive |
| `dispatched_to` | yes | repo name | Self-identifying so the agent can sanity-check it's in the right repo |
| `mode` | yes | `full-autonomy` \| `cancelled` | Cancelled is the kill signal — see [Cancellation](#cancellation) |
| `permissions.*` | yes | enum per field | See defaults below |
| `report_cadence` | yes | `every-phase-transition` \| `every-item` \| `on-change-only` | How often to update `.exec/status.md` |

### Default permissions

Defaults that the dispatcher applies if not overridden in the directive:

| Permission | Default | Meaning |
|---|---|---|
| `commits` | `allow` | Make any commit on a feature branch |
| `prs_open` | `allow` | Open PRs against main |
| `prs_merge` | `allow-on-quality-gate-pass` | Merge a PR only after AAM quality gate passes; otherwise escalate as blocker |
| `install_deps` | `allow-if-needed-for-scope` | Install npm/pip/etc dependencies only if the directive scope requires them |
| `external_api_spend` | `deny` | Never call paid APIs without explicit `allow` in directive |
| `out_of_scope_changes` | `deny` | Stay within the scope; if other code looks broken, surface as blocker, don't fix |

## File format: status

```markdown
---
schema_version: 1
status: starting | running | blocked | done | error | cancelled
directive_id: 2026-04-11-001
started_at: 2026-04-11T17:30:00-07:00
last_updated: 2026-04-11T18:45:00-07:00
current_phase: PLAN | SPEC | EXECUTE | TEST | REVIEW | MERGE | VALIDATE | COMPLETE
current_item: S39-005
context_remaining_pct: 67
heartbeat_ttl_minutes: 15
---

# Summary

One line. Quick state for the executive layer to surface in aggregated views.

# Completed

Items already done with PR links and summaries.

# In Progress

Current item with phase, branch, files modified, test status.

# Blocked (only when status=blocked)

Per-blocker structure:
- What was being attempted
- What failed (with error or evidence)
- Alternatives considered (with rejection reasons)
- Hypothesis about root cause
- Specific question for human
- Working state (uncommitted files, partial work)
- Resume condition (what unblocks this)

# Remaining

What's left from the original directive scope.

# Next Action

What the agent will do when it next runs (resume or completion).
```

### Status lifecycle

```
            ┌──> done
starting ──> running ──┼──> blocked ──(directive updated)──> running ...
            └──> error
            └──> cancelled
```

| Status | Meaning |
|---|---|
| `starting` | Stub written before agent's first phase. Always exists once dispatch fires. |
| `running` | Agent is actively working. Heartbeat must be fresh (within `heartbeat_ttl_minutes`). |
| `blocked` | Agent has stopped cleanly waiting for human input. Full context in `# Blocked` section. |
| `done` | All directive items complete. Agent exited normally. |
| `error` | Agent hit an unrecoverable failure (crash, schema mismatch, infrastructure error). Distinct from `blocked` because there's no clean resume path. |
| `cancelled` | Executive layer set `mode: cancelled` in directive; agent detected at next phase transition and exited. |

## Cancellation

To cancel a running dispatch: rewrite `.exec/directive.md` setting `mode: cancelled`. The per-repo agent checks `mode` at every phase transition. On detecting `cancelled`:

1. Stop work immediately at the current phase boundary (does NOT abort mid-commit or mid-PR)
2. Write final status with `status: cancelled` and a summary of what was completed before the cancel
3. Leave any uncommitted work in place (do not discard)
4. Exit cleanly

The user is then responsible for cleaning up any uncommitted state, or starting a new dispatch.

## Cleanup (end of lifecycle)

The per-repo agent does **not** delete its own `.exec/` on completion — the
executive layer still needs to read the final `done` / `cancelled` / `error`
status. Cleanup is therefore an **executive-layer** responsibility, run once a
terminal status has been observed and surfaced:

1. The `.exec/` payload (directive + final status + append-only history) is
   copied to a timestamped, out-of-tree archive at
   `{ARCHIVE_ROOT}/{repo}/{timestamp}-{directive_id}/`, where `ARCHIVE_ROOT`
   defaults to `{HLPM repo root}/.dispatch-archive` (gitignored — a local,
   portfolio-wide audit store; override via `HLPM_EXEC_ARCHIVE`).
2. `.exec/` is then removed from the consumer repo's working tree, so the
   dispatch tracking files stop lingering as uncommitted local artifacts.

Cleanup only acts on a terminal status (`done`, `cancelled`, `error`); it
refuses to touch a `running`, `blocked`, or `starting` dispatch unless forced.
Two entry points share one script (`.claude/scripts/exec-cleanup.sh`):

- **Automatic** — `/status` cleans every repo it reports in a terminal state, in
  the same run that surfaces the final status.
- **Manual** — `/cleanup [repos]` performs an on-demand sweep.

Because the archive lives outside the consumer repo, the audit trail is
preserved even though `.exec/` is gone from the working tree.

## Heartbeat / stall detection

When the executive layer reads a status file:
- If `status: running` AND `last_updated` is older than `heartbeat_ttl_minutes` (default 15) → treat as **stalled**.
- Stalled status surfaces as a soft blocker in the executive view: "agent in repo X has not updated status in N minutes — investigate".
- The executive layer does NOT auto-restart stalled agents in this iteration. User decides whether to cancel + re-dispatch.

## One active dispatch per repo

The dispatcher refuses to write a new directive if `.exec/status.md` exists with `status: running` (heartbeat fresh) or `status: blocked`. Surfaces conflict to the user with details about the existing dispatch.

To override: user explicitly cancels the existing dispatch first (see [Cancellation](#cancellation)) OR user explicitly approves a force-overwrite which appends both the old directive and old status to `.exec/history.md` before overwriting.

Cross-repo parallelism is unaffected — this rule only applies within a single repo.

## Resume by directive update

When the user clears a blocker, the executive layer **rewrites** the existing `.exec/directive.md` with:

1. The original frontmatter (incremented `dispatched_at`)
2. Original `# Scope`
3. Original `# Constraints`
4. New `# Resume Context` section explaining what was blocked and how it was resolved

The per-repo agent (still alive, parked at the blocker) detects the directive change via file modification time, reads the new `# Resume Context`, updates status to `running`, and continues.

If the per-repo agent has died (crashed, machine restarted, etc.), the resume mechanism falls back to spawning a new session that reads the updated directive. The new session is responsible for picking up from the documented resume point.

## History log

`.exec/history.md` is append-only. Every directive write and status transition appends a snapshot. Format:

```markdown
## 2026-04-11T17:30:00-07:00 — directive dispatched (id 2026-04-11-001)

[snapshot of directive at this moment]

## 2026-04-11T17:35:12-07:00 — status: starting

[snapshot of status]

## 2026-04-11T17:42:08-07:00 — status: running, phase: PLAN

[snapshot]

## 2026-04-11T18:15:45-07:00 — status: blocked

[snapshot]

## 2026-04-11T18:32:00-07:00 — directive updated (resume context added)

[snapshot]
```

The history log persists across dispatches (it does NOT get truncated when a new dispatch starts in the same repo). It is the audit trail.

## What the executive layer needs to provide

These are the components that need to be built in `highest-level-project-management` to use this contract:

1. **`/dispatch` skill** — composes a directive from natural-language input, writes `.exec/directive.md` and the initial `.exec/status.md` stub in the target repo, spawns the background `claude code` process pointed at it.
2. **`/status` skill** — reads `.exec/status.md` from every repo with an active or recent dispatch, aggregates into a unified table, surfaces stalled agents and human blockers.
3. **`/resume` skill** — given a blocker resolution from the user, rewrites the relevant `.exec/directive.md` with a `# Resume Context` section.
4. **`/cancel` skill** — sets `mode: cancelled` in the target repo's `.exec/directive.md`.
5. **`/cleanup` skill** — archives and removes `.exec/` for terminal-status repos (see [Cleanup](#cleanup-end-of-lifecycle)). Also run automatically by `/status` for repos it reports as finished.
6. **Auto-status-on-session-start** — the agent rule in `~/.claude/rules/git-strategy.md` already says "scan working state at session start"; extend this to also call `/status` automatically when the session is in `highest-level-project-management`.

## What AAM needs to provide

These are the components that need to be added to AIAgentMinder for it to work as the per-repo runtime:

1. **Dispatch mode in `sprint-master`** — when a session starts, `sprint-master` checks for `.exec/directive.md`. If present, it enters dispatch mode: reads scope/constraints/permissions/resume-context, runs phase agents autonomously, writes `.exec/status.md` per the cadence, exits cleanly on completion or blocker.
2. **Status writer** — small utility (probably a shell script) called by phase agents at each transition. Writes the status frontmatter + body into `.exec/status.md` and appends to `.exec/history.md`.
3. **Cancellation check** — at every phase transition, sprint-master checks `mode:` in directive. If `cancelled`, exits cleanly with status set.
4. **`.exec/` gitignore template** — added to AAM's shipped `.gitignore` template so consumer repos automatically ignore the dispatch state files.
5. **The bug fixes from the Phase 0 cleanup list** — sprint status header drift, save-before-switch enforcement in `item-executor`, etc. These have to land before dispatch mode can be reliable.

## What's NOT in scope for v1

- **Cross-repo dependencies** (`depends_on:` field for "wait until repo A publishes X"). Manual sequencing by the user is acceptable for now.
- **Auto-restart of stalled or crashed agents.** The user decides whether to cancel + re-dispatch.
- **Backlog-driven autonomous dispatching** ("once a day, check each repo's BACKLOG.md and dispatch if items exist"). This is "Phase 3" — happens after the manual dispatch flow is proven.
- **Multi-machine coordination.** This contract assumes all dispatches run on the same machine (or, more precisely, that the `.exec/` files are accessible to whoever needs to read them).
- **Spending budgets / API cost tracking.** `external_api_spend: deny` is the only cost control in v1.

## Versioning

This contract is `schema_version: 1`. Any breaking change to the directive or status format increments the schema version. Per-repo agents that read a directive with an unrecognized `schema_version` write status with `status: error` and `error: schema_version_mismatch`, then exit. The executive layer surfaces this as a hard blocker requiring an AAM update.

Backwards-compatible additions (new optional fields, new status sub-states) do NOT increment the version.
