---
description: Generate the rolling High-Level Review — diff all of D:/Source against the last snapshot, then refresh the baseline
user-invocable: true
effort: low
---

# /high-level-review — Rolling portfolio state diff

Automated portfolio state diff across **all of `D:/Source`**. Unlike
`/portfolio-review` (the human weekly/monthly/quarterly cadence), this scans
every repo, folder, and loose file on disk directly — no ping-hook dependency —
diffs against the last run, and **replaces the rolling baseline**.

It exists because the event-log summarizer (`hlpm-summarize.sh`) only sees repos
that installed `hlpm-ping.sh`. New repos and the AAM source repo never ping, so
they were invisible. This scan reads the filesystem, so nothing hides.

## Run

1. Execute:

   ```
   python .claude/scripts/hlpm-portfolio-review.py
   ```

   Writes `.hlpm-review/CURRENT-REVIEW.md` (the report) and refreshes
   `.hlpm-review/snapshot.json` (the machine baseline). Both replace the prior run.

2. Read `.hlpm-review/CURRENT-REVIEW.md` and present it, **leading with "What
   changed since last review."** On the first run there is no baseline, so present
   it as the seed inventory and say so.

3. Surface anything actionable, in priority order:
   - **New repos** under `D:/Source` not yet in PROJECT-INDEX.md
   - **New loose files** in the `D:/Source` root (plans/notes that need a home)
   - Repos diverged from `origin` (the `origin Δ` column) or with dirty trees
   - Active / blocked dispatch records (`.exec/status.md`)

## After presenting (offer, never auto-apply)

- Archive a dated copy to `research/review-snapshot-<YYYY-MM-DD>.md` for permanent
  history (`research/` is append-only — never overwrite an existing file).
- Reconcile `PROJECT-INDEX.md` / `PRIORITIES.md` for new or changed repos
  (keep the two in sync per hlpm-conventions.md).
- File loose root files into the right repo or backlog.

## Notes

- **Coordinates with dispatch:** the report folds each repo's `.exec/status.md`
  status into a table — it complements `/status`, it does not replace it.
- **Complements** `hlpm-summarize.sh` (SessionStart event summary) and
  `hlpm-drift-check.sh` (PROJECT-INDEX vs disk).
- The snapshot + current report live under `.hlpm-review/` (gitignored runtime
  state, like `events.jsonl`). The baseline is replaced each run by design;
  durable history lives in `research/` archives and in git.
