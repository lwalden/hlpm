# /resume — Resume a blocked dispatch after clearing the blocker

Rewrite the directive in a blocked repo with a `# Resume Context` section, then re-spawn the agent.

---

## Input

The user provides: repo name + what they did to resolve the blocker. $ARGUMENTS contains the raw input.

Example: "resume my-repo — I fixed the configuration issue, SSE should work now"

Determine SOURCE_ROOT: use `$env:SOURCE_ROOT` env var if set; otherwise infer as the parent directory of this HLPM repo.

## Process

### 1. Validate

- Read `{SOURCE_ROOT}/{repo}/.exec/status.md`
- If status is NOT `blocked`, tell the user: "That repo is not blocked (status: {current}). Nothing to resume."
- If `.exec/directive.md` doesn't exist, tell the user: "No directive found. Nothing to resume."

### 2. Read current state

- Read the `# Blocked` section from status.md — this is the context of what was blocked
- Read the current directive.md — this is the scope/constraints

### 3. Rewrite the directive

Keep the original `# Scope` and `# Constraints` intact. Update:
- `dispatched_at` in frontmatter to current timestamp
- Add `# Resume Context` section at the end:

```markdown
# Resume Context

**Original blocker:** {paste the blocked section from status.md}
**Resolution:** {the user's resolution text}
**Resume from:** {the phase and item from the status file — e.g., "phase EXECUTE on S39-005"}
```

Write the updated directive to `{SOURCE_ROOT}/{repo}/.exec/directive.md`.

### 4. Append to history

Run `bash -c 'cd "{SOURCE_ROOT}/{repo}" && bash .claude/scripts/exec-history-append.sh "directive updated (resume context added)"'`

### 5. Check if agent is still alive

Read `last_updated` from status.md:
- If within 15 minutes (heartbeat fresh): the agent is likely still parked at the blocker. It will detect the directive file change and resume on its own. Report: "Resume context written. The agent should detect the change and continue."
- If older than 15 minutes: the agent has likely died. Spawn a new one:

```bash
cd "{SOURCE_ROOT}/{repo}" && claude -p "DISPATCH MODE: You are resuming from a blocker. Read .exec/directive.md (especially the # Resume Context section) and continue execution from the documented resume point." --agent sprint-master --permission-mode bypassPermissions
```

Run with `run_in_background: true`.

Report: "Agent had exited. Re-spawned with resume context."

### 6. Report

```
Resumed dispatch to {repo}.
Blocker was: {one-line summary of the original blocker}
Resolution: {one-line summary of what the user said}
Resume point: {phase + item from status}
Agent: {still alive — will detect change | re-spawned}
```
