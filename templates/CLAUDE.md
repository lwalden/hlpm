# CLAUDE.md

> Claude reads this file automatically at every session start.
> Keep it concise — every line costs context tokens.

## Project Identity

**Project:** [your-project-name]
**Description:** Top-level tracker for all [your-source-dir] projects — idea pipeline, project index, and review cadences
**Type:** orchestration / documentation
**Stack:** Markdown

## MVP Goals

[Fill in with `/aam-brief`, or write directly]

## Behavioral Rules

### Autonomy Boundaries

**You CAN autonomously:** Create files, install packages, run builds/tests, create branches and PRs, scaffold code

**Only when explicitly asked:** Merge PRs

**Ask the human first:** Create GitHub repos, sign up for services, provide API keys, approve major architectural changes

### Doc-Repo Discipline

This repo is markdown-only — no build, no tests, no code quality gates apply.

- Every IDEAS.md entry is dated on creation
- PIPELINE.md promotions require the scoring matrix to be filled in first (minimum 36/60)
- PROJECT-INDEX.md and PRIORITIES.md must stay in sync — edit both or neither
- Weekly / monthly / quarterly reviews via REVIEW-CHECKLIST.md
- Max 5 active projects at a time
