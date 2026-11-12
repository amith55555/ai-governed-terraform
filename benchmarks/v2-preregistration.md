# Benchmark v2: pre-registration

Written before any v2 run, on 2026-11-12. The tasks, the judge and the runner stay outside the
repo until all runs are done, so the agents cannot read them. After the runs they are added under
`benchmarks/v2/`; the SHA-256 hashes below prove they did not change in between.

- **Why v2:** the v1 tasks were too easy (the plain agent passed CI first time in 8 of 8 runs), and
  v1 mixed "harness" with "harness with sub-agents available".
- **Design:** 3 harder tasks x 2 configurations (baseline; harness without sub-agents) x 2 runs = 12 runs.
- **Start:** git tag `bench-base-v2`. Claude Code in non-interactive mode (`claude -p`) through
  `scripts/agent-session.sh` (agent token, no AWS session), auto permission mode as in every v1 run,
  the Agent tool turned off in both configurations, the same model for every run.
- **Caps:** 45 minutes or 5 USD (Claude Code's own estimate) per run; a run that hits a cap counts as
  a failure. A run cut off by the usage limit is discarded and redone.
- **Judged automatically** from GitHub only: CI checks, the plan artifacts, the diff and the commits.
  Only help allowed: one fixed reply if the agent ends without a pull request.
- **Measures:** success; estimated cost per successful run; CI pushes to green; minutes; tool calls.
- **Decision rule:** the harness helps if it succeeds in at least 2 more of its 6 runs than baseline,
  or, at equal success, has the lower cost per successful run. Otherwise we report that it did not.
- Before this file: a self-test with reference solutions (PRs #71-#76; good solutions passed, bad
  ones failed) and two pilot runs (PRs #77, #78). None of them is part of the v2 results.

| File | SHA-256 |
|---|---|
| `config.sh` | `ab1ef062aa9ff5dd69f49ee855b89afde795ddca6c9bcffa482b65968ea9966e` |
| `run.sh` | `b02765fcdecfdb29201404f069fcffd38456bc4e70d6d3debdf767d470a68ddf` |
| `judge.py` | `d9693843aafa2d19cea8d661eebc3fe21117d7354b9a77d87db5f95acf42d2f8` |
| `facts.py` | `f142fe25f30854a8b0290b09a73c025d8d90428a35fba8d36422430a6d40e0a6` |
| `schedule.sh` | `330f433428959a6bfcdaee90be4da4777f125067df11f82a99559f796688e473` |
| `tasks/C1.txt` | `d9e446e1b028d274687089ec04826720332d4f183e364c8c2df979cbd39c4419` |
| `tasks/C2.txt` | `a67ddabda6a049d2a745603d575552590b5839948f7b997ee810d82686dc45c2` |
| `tasks/C3.txt` | `1bf3456687ef68be1a702ce70ee6cd5c0bb6ae7118686d25bf9aaa7af01cdeba` |
| `patches/C3-planted.patch` | `dcfe281989156b6ad03afe6e0446dfd784ed100c325a7b26c99d07d5d75430b6` |
| `refs/C1-bad.patch` | `a570c6e5937c2524a13dfee1bd22e2c741e1985195e9f6e03585fe970d51e069` |
| `refs/C1-good.patch` | `b57f0e4506c327353b7b6d96fad8e5ad2a588dc03e66141161e93c3b18c7aff1` |
| `refs/C2-bad.patch` | `9307bf237ae5967cc7cca8493764a6ecc55239b35e4ae2f5c18c72d7e5a80e82` |
| `refs/C2-good.patch` | `6170c140e610b9584ce6c2da4d67ddd3e23cbb387552ae2c5d5375e3d632070e` |
| `refs/C3-bad.patch` | `36456e552ac927a94fba1448dc807945ac4be33edf258d65b32a17858447bb96` |
| `refs/C3-good.patch` | `c6fe6660d9caf1fea9cdfc46a672347f3ce9d2d88213773f875b75dbf139fbdb` |
