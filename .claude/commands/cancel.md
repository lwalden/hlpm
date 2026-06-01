# /cancel — Cancel an active dispatch

Set `mode: cancelled` in a repo's directive so the running agent exits cleanly at its next phase transition.

---

## Input

The user provides: repo name. $ARGUMENTS contains the raw input.

Example: "cancel accessi-shield"

## Process

### 1. Validate

- Check if `D:\Source\{repo}\.exec\directive.md` exists
- If not: tell the user "No directive found in {repo}. Nothing to cancel."
- Read `.exec/status.md`:
  - If `status: done` or `status: cancelled`: tell the user "That dispatch already completed/was already cancelled."
  - If `status: blocked`, `running`, or `starting`: proceed with cancellation

### 2. Rewrite directive mode

Read the current `.exec/directive.md`. Change `mode: full-autonomy` (or whatever it is) to `mode: cancelled` in the YAML frontmatter. Write the updated file back.

### 3. Append to history

Run `bash -c 'cd "D:/Source/{repo}" && bash .claude/scripts/exec-history-append.sh "cancellation signal written"'`

### 4. Report

```
Cancel signal written to {repo}.

The agent will detect the change at its next phase transition and exit cleanly.
If the agent has already stalled (last update was {time} ago), it may not detect
the signal. In that case, the process has likely exited and no further action is needed.

Any uncommitted work remains in the repo's working tree.
Use /status to verify the cancellation took effect.
```

## Notes

- This does NOT kill the background process. It writes a signal file that the agent reads.
- The agent checks `mode:` at every phase transition (between PLAN→SPEC, EXECUTE→TEST, etc.)
- If the agent is mid-commit or mid-PR, it finishes that atomic operation before checking
- Uncommitted work is left in place per the dispatch contract — the user decides whether to keep or discard
