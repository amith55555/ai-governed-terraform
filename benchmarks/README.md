# Benchmark

Measures whether the harness (AGENTS.md, hooks, skills, the tf-check MCP server
and the two sub-agents) makes the agent cheaper and more reliable than a plain
setup. The tasks and success criteria were written before any run (W2.8).

## Method

- 4 tasks (`tasks/`) x 2 configurations (baseline, harness) x 2 runs = 16 runs.
- Every run starts from the git tag `bench-base-v1`, in a fresh Claude Code session,
  started with `make agent` (no AWS session, the agent's limited token), with the
  exact prompt from the task file. Same model for every run (`claude-opus-5-5`).
- Each configuration runs in its own copy of the repo, reset before every run by
  `make bench-setup CONFIG=harness|baseline` (`scripts/bench-setup.sh`):
  - **harness**: `~/code/aigt-bench-harness`, the repo as it is at the tag.
  - **baseline**: `~/code/aigt-bench-baseline`, the same commit with the agent config
    removed: `.claude/` (hooks, skills, sub-agents, settings), `AGENTS.md`, `CLAUDE.md`
    and `.mcp.json`. Git is told to ignore those deletions (skip-worktree), so they
    never reach a commit or a pull request.
- CI is the same in both configurations: it is the referee, not part of the harness.
- After a run is recorded, its pull request is closed without merging, and its branch
  deleted. Nothing from a run reaches `main` or AWS.
- Owner settings stay the same for all runs: no user-level `CLAUDE.md`, agents or skills.

## What is recorded

| Metric | Source | Definition |
|---|---|---|
| Tokens (5 types) | `results/usage.csv`, by session ID | input, output, cache write 5 min, cache write 1 h, cache read; sub-agent logs are added to their session |
| Cost | `report.py` with `prices.csv` | tokens x list price per type; never a raw token sum (cache reads cost 5% of input) |
| Success | the task's criteria | every criterion holds, judged from the PR's plan and CI |
| First-pass CI | GitHub | all CI checks pass on the first push |
| CI pushes | GitHub | pushes until all checks pass |
| Stop-hook blocks | the session log | times the completion hook made the agent continue |
| Human interventions | the session log | messages from the human after the prompt |

One row per run goes into `results/runs.csv`, with the PR number. Numbers come from
logs and GitHub only, never from memory. `make usage REPO=<copy>` reads the logs of a
copy; `make bench-report` builds `results/report.md` and fails on missing or
inconsistent data instead of guessing.

## Honesty rules

- Report every run, including failures and runs where the harness did not help.
- The agent can read this folder, so it can see the criteria. They describe
  good engineering, not tricks; a later run can hide the folder if needed.
- Dollar cost is the API list price of the tokens on the date in `prices.csv`, not
  what a subscription charged.
- Usage rows written before W3.4 have one cache-write column; it is counted at the
  cheaper 5-minute price.
- 2 runs per cell are indications, not statistically significant results.
