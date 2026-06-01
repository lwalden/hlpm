---
description: Run the weekly, monthly, or quarterly review cadence from REVIEW-CHECKLIST.md
user-invocable: true
effort: medium
---

# /portfolio-review - Portfolio Review Runner

Drive the REVIEW-CHECKLIST.md cadence interactively. Read current project state, walk the user through the relevant checklist section, and for monthly/quarterly reviews write findings to a dated file in `research/`.

---

## Step 1: Ask cadence (if ambiguous)

Unless the user already named the cadence, ask:

- **Weekly** (~20 min) — Saturdays. Active projects check, focus check, pipeline check, quick wins, next week.
- **Monthly** (~45 min) — around the 15th. Strategic check, pipeline audit, project portfolio review, retrospective.
- **Quarterly** (~90 min) — every 3 months. Vision alignment, kill/launch decisions, goal setting.

If the date makes it obvious (e.g., it's the 15th → monthly is likely due), suggest that one and confirm.

## Step 2: Load context

Before the walkthrough, read:

- `REVIEW-CHECKLIST.md` — the checklist to drive
- `PROJECT-INDEX.md` — what's active, status, priorities
- `PRIORITIES.md` — priority order + rationale
- `IDEAS.md` — recent entries (last 14 days)
- `PIPELINE.md` — anything ready to score or promote
- `BACKLOG.md` — recent additions (last 14 days)
- For monthly/quarterly: `DECISIONS.md` — recent ADRs (last 30/90 days)

Also scan `git log --oneline --since="<cadence-window>"` across `D:\Source\*` to summarize portfolio activity.

## Step 3: Walk the checklist

Go through the relevant section of REVIEW-CHECKLIST.md one checkpoint at a time. For each:

1. Restate the question.
2. Answer what you can from the loaded context (PROJECT-INDEX.md says X, git log shows Y).
3. Ask the user the parts only they can answer (blockers, energy level, intent).
4. Record the answer.

Don't ask everything at once. One checkpoint per turn — this is a conversation, not a survey.

## Step 4: Produce outputs

**Weekly review:** end-of-session summary only. 5-10 bullets covering what moved, what's stuck, next week's #1 thing. No persistent file.

**Monthly review:** write `research/review-monthly-<YYYY-MM>.md` with:

- Accomplishments this month (by project)
- Decisions made (link to DECISIONS.md entries)
- Blockers encountered and how resolved / still pending
- Portfolio changes (active → paused, new launches, kills)
- Next month's focus

**Quarterly review:** write `research/review-quarterly-<YYYY-QN>.md` with everything in monthly plus:

- Vision alignment check — are the active projects still serving the strategic plan?
- Kill/launch decisions — any project that should end, any idea that should start
- Goals for next quarter (3 max)

## Step 5: Update if anything changed

If the walkthrough revealed drift that needs correction NOW (status wrong in PROJECT-INDEX.md, PIPELINE item ready to promote, stale idea to kill), ask the user if you should apply the fixes in this session or log them as BACKLOG items for later.

Never auto-apply without asking — review findings are high-leverage but not urgent.

---

## Notes

- Convention: `research/` is append-only for dated files. Never overwrite an existing review file.
- hlpm-conventions.md: PROJECT-INDEX.md and PRIORITIES.md must stay in sync. If the review surfaces drift between them, flag it explicitly.
- Max 5 active projects rule — if count > 5 during review, surface as finding and ask what pauses.
