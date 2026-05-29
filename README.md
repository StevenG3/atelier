[中文](README.zh.md)

# atelier

A dual-agent collaboration workshop — Designer + Executor + Kanban.

| Role | Who | Responsibility |
|------|-----|----------------|
| Client / Editor | You (human) | Set priorities, start/stop work, gate merges |
| Architect / Reviewer | **Claude** | Architecture decisions, specs, critical PR reviews |
| Craftsperson / Executor | **Codex** | Write code, fix bugs, add tests, refactoring |
| Kanban | **GitHub** | Single source of truth (Issues / PRs / Projects) |

Core principle: **The two agents never talk directly — they communicate only through GitHub reads and writes.** Claude is expensive and reserved for high-leverage thinking; Codex handles all the token-heavy implementation work.

## 📱 Dashboard (open on mobile)

> **One-time setup required** (~1 min, permanent after that):
> 1. Go to repo **Settings → Pages**
> 2. Source → **Deploy from a branch**
> 3. Branch → `main`, directory → `/docs`
> 4. Click **Save** and wait ~1 min for GitHub to build

Dashboard URL after setup:

**https://steveng3.github.io/atelier/dashboard/**

Auto-refreshes every 60 seconds. No login required. Shows all active Issues / PRs, recent Claude-Codex exchanges, and highlights PRs ready for you to merge.

## You only need to do two things

After setup, Claude's scheduled routine handles all intermediate steps automatically:

```
① Create Issue (GitHub mobile) → add claude:design label
              ↓
    Claude auto: write spec → add codex:go → Codex implements
    Claude auto: answer Codex questions, review PRs
              ↓
② Merge PR (tap Merge in GitHub mobile)
```

## Full automated workflow

```
You open Issue (with acceptance criteria + project: <name>) → add claude:design
  → [auto] Claude writes spec → adds codex:go + codex:implement
  → [auto] Codex creates branch, implements
  → [auto] Codex hits blocker → @claude + needs-response
  → [auto] Claude replies with decision → Codex continues
  → [auto] Codex opens PR + claude:review
  → [auto] Claude reviews → Approve
  → [You] Merge PR → loop closed
```

## Manual control (when needed)

```bash
./scripts/atelier.sh status       # view all pending items
./scripts/atelier.sh next         # trigger Claude on highest-priority item now
./scripts/atelier.sh go <N>       # manually add codex:go to Issue #N
./scripts/atelier.sh done <N>     # stop Codex (remove codex:go)
```

Or: GitHub mobile → Actions → "手动触发 Claude" → Run workflow (backup continue button).

## Onboarding a new project

Copy `projects/example.yml` → `projects/<your-project>.yml` and fill in the repo list and test commands.  
When creating a new Issue, put `project: <your-project>` on the first line of the body.

### Active project: Hermes × TradingAgents × Aegis

Config: [`projects/hermes-aegis.yml`](projects/hermes-aegis.yml)  
Repos: `StevenG3/aegis` (core backend) · `StevenG3/hermes-agent` (NL interface) · `StevenG3/tradingagents-official` (market analysis)  
Current phase: 23 (IBKR portfolio reconciliation)

**To generate the next Phase spec**, say in a Claude Code session:
```
atelier design hermes-aegis Phase 24
```
Claude reads Phase 23's Design Notes, writes a complete Phase 24 spec, saves it to `/home/gggqqy/docs/CODEX_PHASE24_PROMPT.md`, and opens an Atelier Issue. You review the spec, then run `./scripts/atelier.sh go <N>` to start Codex.

## First-time setup checklist

1. Install `gh` CLI and run `gh auth login`
2. Enable GitHub Pages (Settings → Pages → main / /docs)
3. Run `bash scripts/sync-labels.sh` to create all required labels
4. Set up Claude Code scheduled routine via `/schedule` (checks pending items every 10 min)
5. Install Codex GitHub App on this repo (triggers on `codex:go` label)

## Document index

| File | Contents |
|------|----------|
| [`CLAUDE.md`](CLAUDE.md) | Claude role, trigger phrases, Q&A protocol |
| [`AGENTS.md`](AGENTS.md) | Codex role, workflow, escalation rules |
| [`docs/workflow.md`](docs/workflow.md) | Kanban columns, label routing, control points |
| [`docs/interaction-protocol.md`](docs/interaction-protocol.md) | Q&A format specification |
| [`prompts/`](prompts/) | Prompt templates for all four operations |
| [`projects/`](projects/) | Per-project config files |
| [`scripts/atelier.sh`](scripts/atelier.sh) | User-side CLI tool |
| [`scripts/preflight.sh`](scripts/preflight.sh) | Startup dependency checks |
| [`tests/`](tests/) | bats unit tests for script logic |
