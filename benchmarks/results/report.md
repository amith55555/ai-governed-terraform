## Benchmark results

| Config | Runs | Success | First-pass CI | CI pushes | Stop-hook blocks | Interventions | API calls | Tokens | Cost |
|---|---|---|---|---|---|---|---|---|---|
| baseline | 8 | 7/8 | 8/8 | 1.0 | 0.0 | 0.0 | 10 | 490,253 | $0.39 |
| harness | 8 | 7/8 | 8/8 | 1.0 | 0.0 | 0.0 | 22 | 1,020,237 | $0.72 |

Averages per run, except Success and First-pass CI.

Harness cost per run vs baseline: +82% ($0.72 vs $0.39).

### By task

| Task | Config | Runs | Success | First-pass CI | API calls | Cost |
|---|---|---|---|---|---|---|
| T1 | baseline | 2 | 2/2 | 2/2 | 10 | $0.33 |
| T1 | harness | 2 | 1/2 | 2/2 | 18 | $0.68 |
| T2 | baseline | 2 | 2/2 | 2/2 | 10 | $0.43 |
| T2 | harness | 2 | 2/2 | 2/2 | 32 | $1.06 |
| T3 | baseline | 2 | 1/2 | 2/2 | 9 | $0.30 |
| T3 | harness | 2 | 2/2 | 2/2 | 10 | $0.29 |
| T4 | baseline | 2 | 2/2 | 2/2 | 13 | $0.52 |
| T4 | harness | 2 | 2/2 | 2/2 | 27 | $0.83 |

### Tokens per run by type

| Config | Input | Output | Cache write 5m | Cache write 1h | Cache read |
|---|---|---|---|---|---|
| baseline | 21 | 4,949 | 0 | 25,428 | 459,854 |
| harness | 48 | 10,479 | 10,447 | 32,625 | 966,637 |

Cost uses list prices: claude-opus-5-5: 4.00/20.00/5.00/8.00/0.20 USD per million tokens (input/output/write 5m/write 1h/read), checked 2026-11-08, https://platform.claude.com/docs/en/about-claude/pricing. It is the API price of the tokens, not what a subscription charged.
With 16 runs, differences are indications, not statistically significant results.
