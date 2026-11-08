#!/usr/bin/env python3

"""Token usage per Claude Code session in a repo, read from Claude Code's own session logs.

A session's sub-agents write their own logs in a folder named after the session
(<session>/.../*.jsonl). Their usage is added to the session, so a run's cost includes
every sub-agent it started. Each API response is counted once, wherever it appears.
"""

import argparse
import csv
import glob
import json
import os
import re
import sys

TOKEN_FIELDS = ["input_tokens", "output_tokens", "cache_write_5m_tokens", "cache_write_1h_tokens", "cache_read_tokens"]
FIELDS = ["session_id", "started", "ended", "models", "api_calls", "subagent_calls",
          *TOKEN_FIELDS, "total_tokens"]


def log_dir(repo, home):
    """Claude Code's folder for this repo, or None."""
    for name in (re.sub(r"[^A-Za-z0-9]", "-", repo), repo.replace("/", "-")):
        path = os.path.join(home, ".claude", "projects", name)
        if os.path.isdir(path):
            return path
    return None


def tokens(usage):
    """The five token counts of one response. Cache writes are split by lifetime (they cost differently)."""
    cache_write = int(usage.get("cache_creation_input_tokens") or 0)
    split = usage.get("cache_creation") if isinstance(usage.get("cache_creation"), dict) else {}
    write_1h = min(int(split.get("ephemeral_1h_input_tokens") or 0), cache_write)
    return {
        "input_tokens": int(usage.get("input_tokens") or 0),
        "output_tokens": int(usage.get("output_tokens") or 0),
        "cache_write_5m_tokens": cache_write - write_1h,
        "cache_write_1h_tokens": write_1h,
        "cache_read_tokens": int(usage.get("cache_read_input_tokens") or 0),
    }


def summarize(session_id, sources):
    """One CSV row. sources: [(lines, from_subagent)], the main log first."""
    row = {"session_id": session_id, "started": "", "ended": "", "api_calls": 0, "subagent_calls": 0}
    row.update({field: 0 for field in TOKEN_FIELDS})
    models, seen = set(), set()
    for source_number, (lines, from_subagent) in enumerate(sources):
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
            key = (message.get("id"), record.get("requestId")) if message.get("id") else ("line", source_number, number)
            if key in seen:
                continue
            seen.add(key)
            row["api_calls"] += 1
            if from_subagent or record.get("isSidechain") is True:
                row["subagent_calls"] += 1
            for field, value in tokens(usage).items():
                row[field] += value
            model = message.get("model")
            if model and not model.startswith("<"):
                models.add(model)
            stamp = record.get("timestamp") or ""
            if stamp and (not row["started"] or stamp < row["started"]):
                row["started"] = stamp
            if stamp > row["ended"]:
                row["ended"] = stamp
    row["models"] = " ".join(sorted(models))
    row["total_tokens"] = sum(row[field] for field in TOKEN_FIELDS)
    return row


def read_lines(path):
    with open(path, encoding="utf-8") as f:
        return f.readlines()


def read_sessions(directory):
    rows = []
    for path in sorted(glob.glob(os.path.join(directory, "*.jsonl"))):
        session_id = os.path.splitext(os.path.basename(path))[0]
        sources = [(read_lines(path), False)]
        sub_dir = os.path.join(directory, session_id)
        for sub in sorted(glob.glob(os.path.join(sub_dir, "**", "*.jsonl"), recursive=True)):
            sources.append((read_lines(sub), True))
        row = summarize(session_id, sources)
        if row["api_calls"]:
            rows.append(row)
    return rows


def upgrade(row):
    """Rows written before W3.4 have one cache_write_tokens column and no sub-agent count.
    Their logs may be gone, so keep the number: it goes into the 5-minute column, the cheaper
    price (stated in benchmarks/README.md)."""
    if "cache_write_5m_tokens" not in row and "cache_write_tokens" in row:
        row["cache_write_5m_tokens"] = row.pop("cache_write_tokens")
        row["cache_write_1h_tokens"] = ""
        row["subagent_calls"] = ""
    return row


def merge(csv_path, new_rows):
    """Add or update rows by session_id; keep rows whose logs no longer exist."""
    rows = {}
    if os.path.exists(csv_path):
        with open(csv_path, newline="", encoding="utf-8") as f:
            rows = {r["session_id"]: upgrade(r) for r in csv.DictReader(f)}
    for row in new_rows:
        rows[row["session_id"]] = row
    ordered = sorted(rows.values(), key=lambda r: r["started"])
    os.makedirs(os.path.dirname(csv_path) or ".", exist_ok=True)
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(ordered)
    return ordered


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--csv", default="benchmarks/results/usage.csv")
    parser.add_argument("--repo", default=os.getcwd(), help="the folder Claude Code ran in (default: here)")
    args = parser.parse_args(argv)
    repo = os.path.realpath(args.repo)
    directory = log_dir(repo, os.path.expanduser("~"))
    if directory is None:
        print(f"FAIL: no Claude Code session logs found for {repo}", file=sys.stderr)
        return 1
    rows = merge(args.csv, read_sessions(directory))
    print(f"{'session':10} {'started':20} {'calls':>5} {'sub':>4} {'input':>8} {'output':>8} "
          f"{'cw_5m':>8} {'cw_1h':>8} {'cache_rd':>10}")
    for r in rows:
        print(f"{r['session_id'][:8]:10} {r['started'][:19]:20} {r['api_calls']:>5} {r.get('subagent_calls') or '':>4} "
              f"{r['input_tokens']:>8} {r['output_tokens']:>8} {r.get('cache_write_5m_tokens') or '':>8} "
              f"{r.get('cache_write_1h_tokens') or '':>8} {r['cache_read_tokens']:>10}")
    print(f"{len(rows)} sessions in {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
