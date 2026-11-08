#!/usr/bin/env python3

"""Benchmark tables for the README, built only from results/runs.csv, results/usage.csv and prices.csv.

Cost is tokens times the list price of each token type (cache reads are about 5% of
the input price), never a raw token sum. Any missing or inconsistent data stops the
report with an error instead of producing a number.
"""

import argparse
import csv
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIGS = ("baseline", "harness")
TASKS = ("T1", "T2", "T3", "T4")
TOKEN_PRICES = {
    "input_tokens": "input",
    "output_tokens": "output",
    "cache_write_5m_tokens": "cache_write_5m",
    "cache_write_1h_tokens": "cache_write_1h",
    "cache_read_tokens": "cache_read",
}


class BadData(Exception):
    pass


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def number(value):
    return int(value) if str(value).strip() else 0


def yes(value, what, run_id):
    if value not in ("yes", "no"):
        raise BadData(f"run {run_id}: {what} must be yes or no, not {value!r}")
    return value == "yes"


def runs_with_usage(runs, usage, prices):
    by_session = {row["session_id"]: row for row in usage}
    seen, result = set(), []
    for run in runs:
        run_id = run["run_id"]
        if run_id in seen:
            raise BadData(f"run {run_id} appears twice")
        seen.add(run_id)
        if run["config"] not in CONFIGS or run["task"] not in TASKS:
            raise BadData(f"run {run_id}: unknown config or task")
        sessions = run["session_id"].split()
        if not sessions:
            raise BadData(f"run {run_id}: no session_id")
        totals = dict.fromkeys(TOKEN_PRICES, 0)
        calls, cost = 0, 0.0
        for session in sessions:
            if session not in by_session:
                raise BadData(f"run {run_id}: session {session} is not in usage.csv (run make usage first)")
            row = by_session[session]
            models = row["models"].split()
            if len(models) != 1 or models[0] not in prices:
                raise BadData(f"run {run_id}: no single priced model for session {session} ({row['models']!r})")
            price = prices[models[0]]
            calls += number(row["api_calls"])
            for field, price_key in TOKEN_PRICES.items():
                count = number(row.get(field, 0))
                totals[field] += count
                cost += count * float(price[price_key]) / 1_000_000
        result.append({
            **run,
            "ok": yes(run["success"], "success", run_id),
            "first_pass": yes(run["first_pass_ci"], "first_pass_ci", run_id),
            "pushes": number(run["ci_pushes"]),
            "stop_blocks": number(run["stop_hook_blocks"]),
            "interventions": number(run["human_interventions"]),
            "calls": calls,
            "tokens": totals,
            "cost": cost,
        })
    return result


def mean(values):
    return statistics.mean(values) if values else 0


def share(items, key):
    return f"{sum(1 for i in items if i[key])}/{len(items)}"


def table(header, rows):
    lines = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    lines += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(lines)


def report(results, price_rows):
    out = ["## Benchmark results", ""]
    by_config = {c: [r for r in results if r["config"] == c] for c in CONFIGS}
    rows = []
    for config, items in by_config.items():
        if not items:
            continue
        rows.append([config, len(items), share(items, "ok"), share(items, "first_pass"),
                     f"{mean([i['pushes'] for i in items]):.1f}", f"{mean([i['stop_blocks'] for i in items]):.1f}",
                     f"{mean([i['interventions'] for i in items]):.1f}", f"{mean([i['calls'] for i in items]):.0f}",
                     f"{mean([sum(i['tokens'].values()) for i in items]):,.0f}", f"${mean([i['cost'] for i in items]):.2f}"])
    out += [table(["Config", "Runs", "Success", "First-pass CI", "CI pushes", "Stop-hook blocks",
                   "Interventions", "API calls", "Tokens", "Cost"], rows),
            "", "Averages per run, except Success and First-pass CI.", ""]

    if all(by_config.values()):
        base, harness = (mean([i["cost"] for i in by_config[c]]) for c in CONFIGS)
        change = (harness - base) / base * 100 if base else 0
        out += [f"Harness cost per run vs baseline: {change:+.0f}% (${harness:.2f} vs ${base:.2f}).", ""]

    rows = []
    for task in TASKS:
        for config in CONFIGS:
            items = [r for r in results if r["task"] == task and r["config"] == config]
            if items:
                rows.append([task, config, len(items), share(items, "ok"), share(items, "first_pass"),
                             f"{mean([i['calls'] for i in items]):.0f}", f"${mean([i['cost'] for i in items]):.2f}"])
    out += ["### By task", "", table(["Task", "Config", "Runs", "Success", "First-pass CI", "API calls", "Cost"], rows), ""]

    rows = []
    for config, items in by_config.items():
        if items:
            rows.append([config] + [f"{mean([i['tokens'][f] for i in items]):,.0f}" for f in TOKEN_PRICES])
    out += ["### Tokens per run by type", "",
            table(["Config", "Input", "Output", "Cache write 5m", "Cache write 1h", "Cache read"], rows), ""]

    sources = "; ".join(f"{p['model']}: {p['input']}/{p['output']}/{p['cache_write_5m']}/{p['cache_write_1h']}/"
                        f"{p['cache_read']} {p['unit']} (input/output/write 5m/write 1h/read), checked {p['checked']}, "
                        f"{p['source']}" for p in price_rows)
    out += [f"Cost uses list prices: {sources}. It is the API price of the tokens, not what a subscription charged.",
            f"With {len(results)} runs, differences are indications, not statistically significant results."]
    return "\n".join(out) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--results", default=os.path.join(HERE, "results"))
    parser.add_argument("--prices", default=os.path.join(HERE, "prices.csv"))
    args = parser.parse_args(argv)
    try:
        price_rows = read_csv(args.prices)
        prices = {p["model"]: p for p in price_rows}
        runs = read_csv(os.path.join(args.results, "runs.csv"))
        if not runs:
            raise BadData("runs.csv has no runs yet")
        results = runs_with_usage(runs, read_csv(os.path.join(args.results, "usage.csv")), prices)
    except (BadData, OSError, KeyError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    text = report(results, price_rows)
    with open(os.path.join(args.results, "report.md"), "w", encoding="utf-8") as f:
        f.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
