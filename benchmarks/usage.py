#!/usr/bin/env python3

"""Token usage per Claude Code session in this repo, read from Claude Code's own session logs."""

import argparse
import csv
import glob
import json
import os
import re
import sys

FIELDS = [
    "session_id", "started", "ended", "models", "api_calls",
    "input_tokens", "output_tokens", "cache_write_tokens", "cache_read_tokens", "total_tokens",
]
TOKEN_KEYS = {
    "input_tokens": "input_tokens",
    "output_tokens": "output_tokens",
    "cache_write_tokens": "cache_creation_input_tokens",
    "cache_read_tokens": "cache_read_input_tokens",
}


def log_dir(repo, home):
    """Claude Code's folder for this repo, or None."""
    for name in (re.sub(r"[^A-Za-z0-9]", "-", repo), repo.replace("/", "-")):
        path = os.path.join(home, ".claude", "projects", name)
        if os.path.isdir(path):
            return path
    return None


def summarize(session_id, lines):
    """One CSV row from the lines of one session log."""
    row = {"session_id": session_id, "started": "", "ended": "", "api_calls": 0}
    row.update({field: 0 for field in TOKEN_KEYS})
    models, seen = set(), set()
    for number, line in enumerate(lines):
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if not isinstance(record, dict) or record.get("type") != "assistant":
            continue
        message = record.get("message") or {}
        usage = message.get("usage")
        if not isinstance(usage, dict):
            continue
        key = (message.get("id"), record.get("requestId")) if message.get("id") else ("line", number)
        if key in seen:
            continue
        seen.add(key)
        row["api_calls"] += 1
        for field, usage_key in TOKEN_KEYS.items():
            row[field] += int(usage.get(usage_key) or 0)
        model = message.get("model")
        if model and not model.startswith("<"):
            models.add(model)
        stamp = record.get("timestamp") or ""
        if stamp and (not row["started"] or stamp < row["started"]):
            row["started"] = stamp
        if stamp > row["ended"]:
            row["ended"] = stamp
    row["models"] = " ".join(sorted(models))
    row["total_tokens"] = sum(row[field] for field in TOKEN_KEYS)
    return row


def read_sessions(directory):
    rows = []
    for path in sorted(glob.glob(os.path.join(directory, "*.jsonl"))):
        with open(path, encoding="utf-8") as f:
            row = summarize(os.path.splitext(os.path.basename(path))[0], f)
        if row["api_calls"]:
            rows.append(row)
    return rows


def merge(csv_path, new_rows):
    """Add or update rows by session_id; keep rows whose logs no longer exist."""
    rows = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="", encoding="utf-8") as f:
            rows = {r["session_id"]: r for r in csv.DictReader(f)}
    for row in new_rows:
        rows[row["session_id"]] = row
    ordered = sorted(rows.values(), key=lambda r: r["started"])
    os.makedirs(os.path.dirname(csv_path) or ".", exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(ordered)
    return ordered


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--csv", default="benchmarks/results/usage.csv")
    args = parser.parse_args(argv)
    repo = os.path.realpath(os.getcwd())
    directory = log_dir(repo, os.path.expanduser("~"))
    if directory is None:
        print(f"FAIL: no Claude Code session logs found for {repo}", file=sys.stderr)
        return 1
    rows = merge(args.csv, read_sessions(directory))
    print(f"{'started':20} {'calls':>5} {'input':>9} {'output':>8} {'cache_wr':>9} {'cache_rd':>10} {'total':>10}")
    for r in rows:
        print(f"{r['started'][:19]:20} {r['api_calls']:>5} {r['input_tokens']:>9} {r['output_tokens']:>8} "
              f"{r['cache_write_tokens']:>9} {r['cache_read_tokens']:>10} {r['total_tokens']:>10}")
    print(f"{len(rows)} sessions in {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
