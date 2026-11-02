# Benchmark

Measures whether the harness (AGENTS.md, hooks, skills, later the tf-check MCP
server and sub-agents) makes the agent cheaper and more reliable than a plain
setup. The tasks and success criteria were written before any run (W2.8).

## Method

- 4 tasks (`tasks/`) x 2 configurations (baseline, harness) x 2 runs = 16 runs.
- Every run starts from the git tag `bench-base-v1`, in a fresh Claude Code session,
  started with `make agent`, with the exact prompt from the task file.
- Baseline: the same repo without `AGENTS.md`, `CLAUDE.md`, `.claude/hooks`,
  `.claude/skills` and the MCP server. Built in week 3.
- CI is the same in both configurations: it is the referee, not part of the harness.

## What is recorded

| Metric | Source | Definition |
|---|---|---|
| Tokens (4 types) | `results/usage.csv`, by session ID | input, output, cache write, cache read; never summed without price weights |
| Success | the task's criteria | every criterion holds, judged from the PR's plan and CI |
| First-pass CI | GitHub | all CI checks pass on the first push |
| CI pushes | GitHub | pushes until all checks pass |
| Stop-hook blocks | the session log | times the completion hook made the agent continue |
| Human interventions | the session log | messages from the human after the prompt |

One row per run goes into `results/runs.csv`. Numbers come from logs and
GitHub only, never from memory.

## Honesty rules

- Report every run, including failures and runs where the harness did not help.
- The agent can read this folder, so it can see the criteria. They describe
  good engineering, not tricks; a later run can hide the folder if needed.
- Dollar cost is computed from token counts with the prices on the run date.
