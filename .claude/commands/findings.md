# /findings — Triage AAM tooling findings

Triage the tooling-findings inbox: findings about AIAgentMinder itself (defects, friction, feature gaps) captured by sprint retrospectives across consumer repos. The write side is AAM's `hlpm-finding.sh`, which appends to `tooling-findings.jsonl` in the HLPM root. This command is the only consumer that removes entries.

---

## Input

No arguments required. Optionally filter by repo, type, or severity: $ARGUMENTS

## Process

### 1. Read the inbox

Read `tooling-findings.jsonl` from the HLPM root. If the file is missing or empty, report "No untriaged tooling findings." and stop.

Each line is a JSON record: `ts`, `repo`, `branch`, `sprint`, `type` (defect | friction | feature), `severity` (low | medium | high), `summary`, `detail`, `aam_version`.

### 2. Group duplicates

Cluster findings that describe the same underlying issue reported from different repos or sprints (same symptom, same script/agent, same platform). A finding that fired from 4 repos is one issue with 4 confirmations — strong evidence it is real, not environment noise.

### 3. Check against current AAM state

Determine `SOURCE_ROOT` (the `SOURCE_ROOT` env var, else the parent directory of this repo). For each group, check whether the issue is already tracked or fixed:

- `{SOURCE_ROOT}/AIAgentMinder/BACKLOG.md` — existing backlog item covering it?
- `{SOURCE_ROOT}/AIAgentMinder/CHANGELOG.md` and git log since the finding's `ts` — already fixed? Compare the finding's `aam_version` against the current version.

### 4. Present groups and recommend dispositions

Present each group: summary, type/severity, repos and sprints affected, environment detail, already-tracked/fixed evidence. Recommend one disposition per group and confirm with the user before acting:

- **Promote** — add to AAM's own backlog. Run in the AIAgentMinder repo:
  ```bash
  cd {SOURCE_ROOT}/AIAgentMinder
  bash bin/backlog-capture.sh add <type> "<title>" "retro:<repo[,repo]>"
  bash bin/backlog-capture.sh detail <id> "<environment detail, affected repos, aam_version, original finding timestamps>"
  ```
  Type mapping: `defect` → `defect`, `feature` → `feature`, `friction` → `chore` (or `spike` if investigation is needed first).
- **Escalate** — open a GitHub issue on the public AIAgentMinder repo. Only for findings the user judges universal (not specific to this machine, shell, or customizations), and **only with explicit per-finding user confirmation** — never auto-file.
- **Dismiss** — already fixed, superseded, or environment noise not worth tracking. Record the reason.

### 5. Archive and clear

For each disposed group:

1. Append each original record to `tooling-findings-archive.jsonl` in the HLPM root, with two added fields: `disposed_at` (ISO 8601 UTC) and `disposition` (`promoted:B-NNN` | `escalated:#NNN` | `dismissed:<short reason>`).
2. Rewrite `tooling-findings.jsonl` keeping only undisposed lines; delete the file if none remain.

Findings the user defers stay in the inbox untouched and resurface at the next session start.

## Notes

- Both `tooling-findings.jsonl` and `tooling-findings-archive.jsonl` are gitignored runtime state — never commit them.
- The weekly review (`REVIEW-CHECKLIST.md`) includes a findings-triage checkpoint so the inbox cannot silently accumulate.
