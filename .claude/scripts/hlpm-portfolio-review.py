#!/usr/bin/env python3
"""
HLPM High-Level Review generator.

Scans every git repo, non-git folder, and loose file under D:/Source, diffs the
current state against the last-run snapshot, writes a fresh "what changed" report
that REPLACES the previous one, and rolls the snapshot baseline forward.

Complements (does not replace):
  - /portfolio-review  : human strategic cadence (weekly/monthly/quarterly)
  - hlpm-summarize.sh  : SessionStart event-log summary (needs ping-hook coverage)
  - hlpm-drift-check.sh: PROJECT-INDEX vs disk

Unlike the event-log summarizer, this scans ALL repos on disk directly, so it
sees repos that never installed the ping hook (the coverage gap that hid bots,
saas-template, and aiagentminder from events.jsonl).

Outputs (both under .hlpm-review/, gitignored runtime state like events.jsonl):
  - snapshot.json       : machine-readable rolling baseline (replaced each run)
  - CURRENT-REVIEW.md   : human-readable report           (replaced each run)
"""
import json
import os
import subprocess
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
HLPM_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
SRC_ROOT = os.path.abspath(os.path.join(HLPM_DIR, ".."))
STATE_DIR = os.path.join(HLPM_DIR, ".hlpm-review")
SNAPSHOT = os.path.join(STATE_DIR, "snapshot.json")
REPORT = os.path.join(STATE_DIR, "CURRENT-REVIEW.md")
SCHEMA_VERSION = 1
ACTIVE_DAYS = 30


def git(repo, *args):
    """Run a git command in repo; return stripped stdout or '' on any failure."""
    try:
        r = subprocess.run(
            ["git", "-C", repo, *args],
            capture_output=True, text=True, timeout=20,
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def parse_iso(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def read_dispatch(repo_path):
    """Return (status, directive_id, last_updated) from .exec/status.md, or None."""
    f = os.path.join(repo_path, ".exec", "status.md")
    if not os.path.isfile(f):
        return None
    status = directive = updated = ""
    try:
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if line.startswith("status:") and not status:
                    status = line.split(":", 1)[1].strip()
                elif line.startswith("directive_id:") and not directive:
                    directive = line.split(":", 1)[1].strip()
                elif line.startswith("last_updated:") and not updated:
                    updated = line.split(":", 1)[1].strip()
                elif line == "---" and status:
                    break
    except Exception:
        return None
    return {"status": status, "directive_id": directive, "last_updated": updated}


def scan_repo(name, path):
    head = git(path, "rev-parse", "HEAD")
    branch = git(path, "rev-parse", "--abbrev-ref", "HEAD") or "?"
    last_date = git(path, "log", "-1", "--format=%cI")
    last_subj = git(path, "log", "-1", "--format=%s")
    dirty_raw = git(path, "status", "--porcelain")
    dirty = len([x for x in dirty_raw.splitlines() if x.strip()]) if dirty_raw else 0
    ab = git(path, "rev-list", "--left-right", "--count", "origin/HEAD...HEAD")
    behind = ahead = None
    if ab and "\t" in ab:
        try:
            b, a = ab.split("\t")
            behind, ahead = int(b), int(a)
        except Exception:
            pass
    return {
        "head": head,
        "branch": branch,
        "last_commit_date": last_date,
        "last_subject": last_subj,
        "dirty": dirty,
        "behind": behind,
        "ahead": ahead,
        "dispatch": read_dispatch(path),
    }


def scan():
    repos, non_git_dirs, root_files = {}, [], []
    try:
        entries = sorted(os.scandir(SRC_ROOT), key=lambda e: e.name.lower())
    except Exception:
        entries = []
    for e in entries:
        try:
            if e.is_dir():
                if os.path.isdir(os.path.join(e.path, ".git")):
                    repos[e.name] = scan_repo(e.name, e.path)
                else:
                    non_git_dirs.append(e.name)
            elif e.is_file():
                root_files.append(e.name)
        except Exception:
            continue
    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "repos": repos,
        "non_git_dirs": non_git_dirs,
        "root_files": root_files,
    }


def commits_between(path, old_head, new_head, since_iso):
    """Subjects of commits added since the baseline. Prefer old..new; fall back
    to --since when old_head is unreachable (rebase/force-push/unknown)."""
    subs = ""
    if old_head and new_head and old_head != new_head:
        subs = git(path, "log", f"{old_head}..{new_head}", "--format=%s")
    if not subs and since_iso:
        subs = git(path, "log", f"--since={since_iso}", "--format=%s")
    return [s for s in subs.splitlines() if s.strip()] if subs else []


def md_table(headers, rows):
    if not rows:
        return "_none_\n"
    out = "| " + " | ".join(headers) + " |\n"
    out += "| " + " | ".join("---" for _ in headers) + " |\n"
    for r in rows:
        out += "| " + " | ".join(str(c) for c in r) + " |\n"
    return out


def render(cur, prev):
    now = parse_iso(cur["generated_at"])
    lines = []
    lines.append(f"# Highest-Level Review — {cur['generated_at'][:16].replace('T', ' ')} UTC\n")
    nrepo, ndir, nfile = len(cur["repos"]), len(cur["non_git_dirs"]), len(cur["root_files"])
    if prev:
        lines.append(f"**Baseline:** {prev['generated_at'][:16].replace('T', ' ')} UTC")
    else:
        lines.append("**Baseline:** none — this is the first snapshot (seeding the rolling baseline)")
    lines.append(f"**Scope:** `D:/Source` — {nrepo} git repos · {ndir} non-git folders · {nfile} loose files\n")

    # ---- What changed ----
    if prev:
        lines.append(f"## What changed since {prev['generated_at'][:10]}\n")
        prev_repos, cur_repos = set(prev["repos"]), set(cur["repos"])
        prev_files, cur_files = set(prev.get("root_files", [])), set(cur["root_files"])

        new_repos = sorted(cur_repos - prev_repos)
        gone_repos = sorted(prev_repos - cur_repos)
        new_files = sorted(cur_files - prev_files)
        gone_files = sorted(prev_files - cur_files)

        lines.append("### New repos")
        if new_repos:
            for n in new_repos:
                r = cur["repos"][n]
                lines.append(f"- **{n}** — branch `{r['branch']}`, last: {r['last_subject']} ({(r['last_commit_date'] or '')[:10]})")
        else:
            lines.append("- _none_")
        lines.append("")

        lines.append("### New loose files in D:/Source root")
        lines.extend([f"- `{n}`" for n in new_files] or ["- _none_"])
        lines.append("")

        # Repos with new commits
        lines.append("### Repos with new commits")
        any_change = False
        for n in sorted(cur_repos & prev_repos):
            c, p = cur["repos"][n], prev["repos"][n]
            if c["head"] and c["head"] != p.get("head"):
                any_change = True
                subs = commits_between(os.path.join(SRC_ROOT, n), p.get("head"), c["head"], prev["generated_at"])
                lines.append(f"- **{n}** — +{len(subs)} commit(s) · branch `{c['branch']}`")
                for s in subs[:6]:
                    lines.append(f"    - {s}")
                if len(subs) > 6:
                    lines.append(f"    - …and {len(subs) - 6} more")
        if not any_change:
            lines.append("- _none_")
        lines.append("")

        # Branch switches
        lines.append("### Branch switches")
        switched = False
        for n in sorted(cur_repos & prev_repos):
            c, p = cur["repos"][n], prev["repos"][n]
            if c["branch"] != p.get("branch"):
                switched = True
                lines.append(f"- **{n}**: `{p.get('branch')}` → `{c['branch']}`")
        if not switched:
            lines.append("- _none_")
        lines.append("")

        if gone_repos or gone_files:
            lines.append("### Removed")
            lines.extend([f"- repo gone: **{n}**" for n in gone_repos])
            lines.extend([f"- file gone: `{n}`" for n in gone_files])
            lines.append("")
    else:
        lines.append("## First baseline\n")
        lines.append("No prior snapshot. Recorded current state of every repo, folder, and loose "
                     "file. Future `/high-level-review` runs will diff against this. Below is the "
                     "current inventory so the seed itself is reviewable.\n")

    # ---- Current inventory ----
    active, dormant = [], []
    for n in sorted(cur["repos"]):
        r = cur["repos"][n]
        d = parse_iso(r["last_commit_date"])
        days = (now - d).days if (d and now) else None
        is_active = days is not None and days <= ACTIVE_DAYS
        ab = "—"
        if r["behind"] is not None and r["ahead"] is not None:
            ab = f"{r['behind']}↓/{r['ahead']}↑"
        flags = []
        if r["dirty"]:
            flags.append(f"{r['dirty']} dirty")
        if r["branch"] not in ("main", "master", "?"):
            flags.append("off-main")
        flag_s = ", ".join(flags) or "—"
        date_s = (r["last_commit_date"] or "")[:10]
        if is_active:
            active.append((n, r["branch"], date_s, ab, flag_s))
        else:
            dormant.append((n, r["branch"], date_s, flag_s))

    lines.append(f"## Portfolio snapshot — active (commit in last {ACTIVE_DAYS}d)\n")
    lines.append(md_table(["repo", "branch", "last commit", "origin Δ", "flags"], active))
    lines.append(f"\n## Portfolio snapshot — dormant ( > {ACTIVE_DAYS}d )\n")
    lines.append(md_table(["repo", "branch", "last commit", "flags"], dormant))

    # Dispatches
    disp_rows = []
    for n in sorted(cur["repos"]):
        d = cur["repos"][n].get("dispatch")
        if d:
            disp_rows.append((n, d["status"] or "?", d["directive_id"] or "—", (d["last_updated"] or "")[:10]))
    lines.append("\n## Active dispatch records (.exec/status.md)\n")
    lines.append(md_table(["repo", "status", "directive", "updated"], disp_rows))

    # Non-git + loose
    lines.append("\n## Non-git folders\n")
    lines.extend([f"- `{n}`" for n in cur["non_git_dirs"]] or ["- _none_"])
    lines.append("\n## Loose files in D:/Source root\n")
    lines.extend([f"- `{n}`" for n in cur["root_files"]] or ["- _none_"])

    lines.append("\n---")
    lines.append("_Generated by `/high-level-review`. Snapshot baseline rolled forward in "
                 "`.hlpm-review/snapshot.json`; this report replaces the prior `CURRENT-REVIEW.md`._")
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(STATE_DIR, exist_ok=True)
    prev = None
    if os.path.isfile(SNAPSHOT):
        try:
            with open(SNAPSHOT, encoding="utf-8") as f:
                prev = json.load(f)
        except Exception:
            prev = None
    cur = scan()
    report = render(cur, prev)
    with open(REPORT, "w", encoding="utf-8") as f:
        f.write(report)
    with open(SNAPSHOT, "w", encoding="utf-8") as f:
        json.dump(cur, f, indent=2)
    baseline = prev["generated_at"][:16] if prev else "FIRST RUN (no prior baseline)"
    print(f"High-level review written: {REPORT}")
    print(f"Baseline diffed against: {baseline}")
    print(f"Scanned: {len(cur['repos'])} repos, {len(cur['non_git_dirs'])} non-git folders, {len(cur['root_files'])} loose files")


if __name__ == "__main__":
    main()
