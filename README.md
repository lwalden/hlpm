# HLPM — Highest-Level Project Management

A Claude Code plugin for solo developers managing a portfolio of repos from a single meta-tracker.

## What it does

- **Portfolio state surface** — `PROJECT-INDEX.md`, `PRIORITIES.md`, and `docs/dispatch-contract.md` answer "what's active, paused, and how do repos relate" without scanning the filesystem
- **Dispatch executive layer** — `/dispatch`, `/status`, `/resume`, `/cancel`, `/cleanup` commands drive autonomous Claude sessions in consumer repos via AIAgentMinder, and archive away their tracking artifacts when finished
- **Drift defense** — session-boundary event log + read-time enrichment surfaces what changed across repos since your last HLPM session
- **Tooling-findings triage** — `/findings` triages findings about AIAgentMinder itself, captured by sprint retros in consumer repos (promote to the AAM backlog, escalate to a GitHub issue, or dismiss)
- **Review cadence** — weekly / monthly / quarterly reviews from `REVIEW-CHECKLIST.md`
- **Ecosystem MCP server** — optional local service registry (`scripts/mcp-server.ts`) so Claude knows your local services before recommending external APIs
- **Dispatch watcher** — Windows Scheduled Task (`scripts/dispatch-watcher.ps1`) auto-resumes stalled dispatches after context cycles

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI
- [AIAgentMinder](https://github.com/lwalden/AIAgentMinder) installed in each consumer repo you want to dispatch to
- Bash (Git Bash, WSL, or macOS/Linux terminal) for hook scripts
- Node.js 18+ (for the optional MCP server)

## Quick start

1. **Clone or fork this repo** as your HLPM directory:
   ```bash
   git clone https://github.com/lwalden/hlpm ~/hlpm
   cd ~/hlpm
   ```

2. **Copy the starter templates** into your HLPM root:
   ```bash
   cp templates/CLAUDE.md .
   cp templates/PROJECT-INDEX.md .
   cp templates/PRIORITIES.md .
   cp templates/IDEAS.md .
   cp templates/PIPELINE.md .
   cp templates/DECISIONS.md .
   cp templates/REVIEW-CHECKLIST.md .
   ```

3. **Set environment variables** in your shell profile (`.bashrc`, `.zshrc`, or PowerShell `$PROFILE`):
   ```bash
   export HLPM_DIR="/absolute/path/to/your/hlpm"
   export SOURCE_ROOT="/absolute/path/to/your/repos"
   ```
   These tell the hook scripts where to find the HLPM event log and where your repos live.

4. **Fill in your portfolio** — edit `CLAUDE.md`, `PROJECT-INDEX.md`, and `PRIORITIES.md` to describe your projects. Or open Claude Code and run `/aam-brief` to fill in `CLAUDE.md` interactively.

5. **Open Claude Code** in your HLPM directory. The hooks in `.claude/settings.json` wire up automatically.

## Optional: ecosystem MCP server

Registers your local services with Claude so it recommends them before external APIs:

```bash
cd scripts && npm install
cp ../ecosystem/services.example.json ../ecosystem/services.json
cp ../ecosystem/integration-prefs.example.json ../ecosystem/integration-prefs.json
# Edit services.json and integration-prefs.json for your stack
npm run build
```

Then add to your HLPM's `.mcp.json`:
```json
{
  "mcpServers": {
    "hlpm-ecosystem": {
      "command": "node",
      "args": ["scripts/dist/mcp-server.js"]
    }
  }
}
```

## Optional: dispatch watcher (Windows)

Auto-resumes stalled dispatches after context cycles — run once, elevated:

```powershell
pwsh -File scripts/install-dispatch-watcher.ps1
```

## Consumer repo setup

For each repo you want to dispatch work to, install AIAgentMinder:

```bash
npx aiagentminder@latest sync --apply
```

The `hlpm-ping.sh` hook (installed by AAM) reads `$HLPM_DIR` to write session events back to your HLPM event log.

## Dispatch usage

Open Claude Code in your HLPM directory, then:

```
/dispatch to my-repo: work the next 3 sprint items
/status
/resume my-repo
/cancel my-repo
/cleanup my-repo
/high-level-review
/portfolio-review
```

See `docs/dispatch-contract.md` for the full contract schema.

## Repository layout

```
.claude/
  agents/     Sprint-master, planner, speccer, QA, review lenses, and more
  commands/   /dispatch, /status, /resume, /cancel, /cleanup, /portfolio-review, /high-level-review
  rules/      Universal Claude Code rules (git discipline, tool-first, context cycling)
  scripts/    Hook scripts, backlog manager, drift detector, session summarizer
  skills/     AAM skill shortcuts
  settings.json  Hook wiring (PreToolUse, SessionStart/End, PostToolUse, Stop)
scripts/
  mcp-server.ts               Ecosystem MCP server (TypeScript)
  dispatch-watcher.ps1        Windows watcher for unattended context-cycle resume
  install-dispatch-watcher.ps1  Registers the watcher as a Scheduled Task
ecosystem/
  services.example.json          Template for your local service registry
  integration-prefs.example.json Template for AI/automation integration preferences
templates/
  CLAUDE.md, PROJECT-INDEX.md, PRIORITIES.md, IDEAS.md, PIPELINE.md, DECISIONS.md, REVIEW-CHECKLIST.md
docs/
  dispatch-contract.md  Schema v1 for the HLPM ↔ consumer-repo dispatch protocol
```

## Related

- [AIAgentMinder](https://github.com/lwalden/AIAgentMinder) — the per-repo agent framework HLPM dispatches to
