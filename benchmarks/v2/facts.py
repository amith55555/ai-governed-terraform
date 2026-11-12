#!/usr/bin/env python3
"""Facts for benchmark v2 runs, from Claude Code's JSON output, its session logs and GitHub.

  facts.py status AGENT_JSON PREVIOUS   -> ok | limited | budget-cap | time-cap | agent-error
  facts.py session AGENT_JSON           -> the session ID
  facts.py row RESULTS RUN_ID TASK CONFIG AGENT COPY OUT PR STATUS FIXED MINUTES PLANTED
"""
import collections
import csv
import datetime
import glob
import json
import os
import re
import subprocess
import sys

MAIN = os.path.expanduser("~/code/ai-governed-terraform")
LIMIT = re.compile(r"usage limit|hit your limit|limit reached|rate.?limit", re.I)
FIELDS = ["run_id", "task", "config", "agent", "date", "session_ids", "pr", "status", "success", "ci_pushes",
          "first_pass_ci", "minutes", "cost_estimate_usd", "turns", "tool_calls", "guard_blocks", "tools",
          "fixed_reply", "planted", "failed_checks", "notes"]


def result_of(path):
    """The last JSON object Claude Code printed (the launcher prints one plain line first)."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = [line for line in f if line.lstrip().startswith("{")]
        return json.loads(lines[-1]) if lines else None
    except (OSError, ValueError):
        return None


def status(path, previous):
    if previous != "ok":
        return previous
    result = result_of(path)
    if result is None:
        return "agent-error"
    text = str(result.get("result", "")) + " " + str(result.get("subtype", ""))
    if result.get("is_error") and LIMIT.search(text):
        return "limited"
    if "budget" in str(result.get("subtype", "")):
        return "budget-cap"
    return "agent-error" if result.get("is_error") else "ok"


def gh_json(*args):
    out = subprocess.run(["gh", *args], cwd=MAIN, capture_output=True, text=True).stdout.strip()
    return json.loads(out) if out else None


def log_facts(copy, session_ids):
    folder = os.path.expanduser("~/.claude/projects/") + re.sub(r"[^A-Za-z0-9]", "-", copy)
    tools, blocks = collections.Counter(), 0
    for sid in session_ids:
        for path in glob.glob(f"{folder}/{sid}.jsonl") + glob.glob(f"{folder}/{sid}/subagents/*.jsonl"):
            with open(path, encoding="utf-8") as f:
                for line in f:
                    entry = json.loads(line)
                    content = (entry.get("message") or {}).get("content")
                    if not isinstance(content, list):
                        continue
                    for part in content:
                        if not isinstance(part, dict):
                            continue
                        if part.get("type") == "tool_use":
                            tools[part["name"].replace("mcp__tf-check__", "tf-check ")] += 1
                        if part.get("type") == "tool_result" and "BLOCKED by pre-tool guard" in json.dumps(part):
                            blocks += 1
    return tools, blocks


def ci_facts(pr, planted):
    """Pushes that CI ran on (only this PR's own commits), and whether the first one passed."""
    view = gh_json("pr", "view", pr, "--json", "commits,headRefName") or {}
    shas = [c["oid"] for c in view.get("commits", []) if c["oid"] != planted]
    runs = gh_json("run", "list", "--branch", view.get("headRefName", ""), "--workflow", "pr.yml", "--limit", "50",
                   "--json", "databaseId,headSha,event,conclusion") or []
    runs = sorted((r for r in runs if r["event"] == "pull_request" and r["headSha"] in shas), key=lambda r: r["databaseId"])
    pushed = list(dict.fromkeys(r["headSha"] for r in runs))
    first = runs[0]["conclusion"] == "success" if runs else False
    return len(pushed), first


def row(args):
    results, run_id, task, config, agent, copy, out, pr, run_status, fixed, minutes, planted = args
    outputs = [r for r in (result_of(os.path.join(out, f)) for f in ("agent.json", "agent2.json")) if r]
    session_ids = list(dict.fromkeys(r.get("session_id", "") for r in outputs if r.get("session_id")))
    tools, blocks = log_facts(copy, session_ids)
    pushes, first = ci_facts(pr, planted) if pr else (0, False)
    with open(os.path.join(out, "verdict.json"), encoding="utf-8") as f:
        verdict = json.load(f)
    record = {
        "run_id": run_id, "task": task, "config": config, "agent": agent,
        "date": datetime.date.today().isoformat(), "session_ids": " ".join(session_ids), "pr": pr,
        "status": run_status, "success": "yes" if verdict.get("success") and run_status == "ok" else "no",
        "ci_pushes": pushes, "first_pass_ci": "yes" if first else "no", "minutes": minutes,
        "cost_estimate_usd": f"{outputs[-1].get('total_cost_usd', 0):.2f}" if outputs else "",
        "turns": sum(r.get("num_turns", 0) for r in outputs), "tool_calls": sum(tools.values()),
        "guard_blocks": blocks, "tools": ";".join(f"{k}:{v}" for k, v in sorted(tools.items())),
        "fixed_reply": fixed, "planted": planted[:7],
        "failed_checks": ";".join(k for k, v in verdict.get("checks", {}).items() if not v),
        "notes": "; ".join(verdict.get("notes", [])),
    }
    new = not os.path.exists(results)
    with open(results, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDS)
        if new:
            writer.writeheader()
        writer.writerow(record)


if __name__ == "__main__":
    command = sys.argv[1]
    if command == "status":
        print(status(sys.argv[2], sys.argv[3]))
    elif command == "session":
        print((result_of(sys.argv[2]) or {}).get("session_id", ""))
    elif command == "row":
        row(sys.argv[2:])
