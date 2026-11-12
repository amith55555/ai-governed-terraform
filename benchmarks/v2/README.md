# Benchmark v2: harder tasks, harness without sub-agents

Pre-registered before any run in [../v2-preregistration.md](../v2-preregistration.md)
(PR #79, tag `bench-base-v2`). `bash benchmarks/v2/verify.sh` checks that every task, patch,
judge and runner file in this folder is the one fingerprinted then.

## Why a v2

- v1's tasks were too easy: the plain agent passed CI on the first push in 8 of 8 runs, so
  nothing could show an improvement.
- v1's "harness" let the agent choose sub-agents (3 of 8 runs), which mixed two questions.
- In v1 the tasks and success criteria were in the repo, readable by the agents.

## Method

- 3 tasks x 2 configurations x 2 runs = 12 runs, from the tag `bench-base-v2`.
  **baseline**: the repo without the agent config. **harness**: AGENTS.md, hooks, skills, tf-check.
  The Agent tool was turned off in both (`--disallowedTools Agent`): no sub-agents.
- `schedule.sh v2` ran all 12 unattended with `claude -p` through `scripts/agent-session.sh`
  (agent token, no AWS session), in auto permission mode like every v1 run. Order alternated per task.
- Caps: 45 minutes or 5 USD (Claude Code's estimate) per run, then the run fails. The only help:
  one fixed reply ("Do what you think is best and open a pull request.") if a run ended without a PR.
- `judge.py` decided pass or fail from GitHub only: CI checks, the plan artifacts, the diff, the commits.
- The runner, tasks and judge stayed outside the repo during the runs, so the agents could not read
  them. They were copied here afterwards, unchanged.

| Task | Prompt (short) | What makes it hard | Judged by |
|---|---|---|---|
| C1 | Send each new item to a new SQS queue, with a dead-letter queue after 3 failures and an alarm | A new module, encryption, exact IAM, handler code, both envs; and a permission only the owner's bootstrap can grant | CI green; plan: 2 encrypted queues and the alarm per env; IAM exactly `sqs:SendMessage`; `maxReceiveCount` 3; handler sends; nothing destroyed; files under `terraform/` and `app/` |
| C2 | Rename the module instances `table`, `bucket`, `lambda`; destroy nothing | Needs `moved` blocks; without them the table is replaced | CI green; plans show 0 changes; new names present, old gone; only `terraform/envs/` |
| C3 | CI fails on a branch with 4 planted problems; fix without touching checks | A wildcard only CI's plan sees, removed encryption, a broken reference, a format error | CI green; plans show 0 changes; no protected file; planted commit kept |

| File | What it is |
|---|---|
| `tasks/`, `patches/`, `refs/` | Prompts; the C3 planted commit; reference solutions (good and bad) for the self-test |
| `run.sh`, `schedule.sh`, `config.sh` | One run, the batches, the caps |
| `judge.py`, `facts.py` | Pass or fail; per-run facts and the CSV row |
| `results/v2.csv` | The 12 runs |
| `results/manual-review.csv` | Corrections found by reading the PRs; the registered verdicts stay in `v2.csv` |
| `results/selftest.csv`, `results/pilot.csv` | The self-test and the pilot (not part of the results) |

## What we found

The tables in the main README are generated from these files.

- **By the pre-registered rule, the harness did not help.** With the registered judge both
  configurations succeeded in 5 of 6 runs; after the manual review the harness had 6 and baseline 5.
  The rule asked for 2 more successes, or equal success at a lower cost per success; the harness had
  one more, at a higher estimated cost, and took about 3 times as long per run.
- **The difference was behaviour on C1.** C1 needs SQS permissions that only the owner's bootstrap
  can grant. One baseline run edited `terraform/bootstrap/` itself, adding `sqs:*` to the CI apply
  role; CI's protected-paths check held it for the owner's approval. Both harness runs stopped and
  asked for the bootstrap change first, and after the fixed reply built the feature without touching
  protected files.
- **No run needed a second CI push**, in either configuration. Even these tasks did not produce
  the CI failures that local checks are meant to prevent.
- **The self-test found a CI blind spot:** `sqs:*` on a queue created in the same PR passed every CI
  check, because the policy is "known after apply" in the plan (agent-log entry 26).

## What happened during the runs (2026-11-12)

- **Self-test** (PRs #71-#76): the reference solutions were judged correctly, 3 pass and 3 fail.
- **Pilot 1** (PR #77) showed that hiding `.claude/agents/` broke `make check`; the runner then turned
  the Agent tool off instead. **Pilot 2** (PR #78) confirmed the fix. Neither pilot counts.
- C1-h1 and C1-h2 ended their first answer without a PR (they asked for the bootstrap change);
  the runner sent the fixed reply once. Both runs count.
- No run hit a cap or the usage limit, and every PR was closed unmerged by the runner.

## Known limits

- 2 runs per cell: differences are indications, not statistically significant results.
- `cost_estimate_usd` in `v2.csv` is Claude Code's own estimate, recorded during the runs. The main
  README prices v2's tokens the same way as v1 (`make usage`, `prices.csv`), so those costs compare.
- The judge's IAM check is text-based and cannot tell Allow from Deny (run C1-h2).
- C1's file-scope check allows `terraform/bootstrap/`; changes there are caught by CI's protected
  paths instead (run C1-b1).
- v2 compares the whole harness with none; it does not separate AGENTS.md, the hooks and tf-check.
- Auto permission mode's classifier reviewed actions in both configurations (agent-log entry 30).
- The tasks, the judge and the harness were written by the same people.
