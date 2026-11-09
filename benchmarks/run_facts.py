#!/usr/bin/env python3
"""Facts for one benchmark run, from Claude Code's logs and GitHub. Prints a draft runs.csv row.

Usage (from the main repo, after the run):
  python3 -I benchmarks/run_facts.py --config harness --task T1 --run 1 --pr 41
You still judge `success` against the task's criteria and count `human_interventions`;
the row has `?` there until you fill them in.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usage  # noqa: E402

ATTEMPT = re.compile(r"make check failed \(attempt (\d) of 3\)")


def gh_json(*args):
    out = subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def newest_session(log_folder):
    files = glob.glob(os.path.join(log_folder, "*.jsonl"))
    if not files:
        raise SystemExit(f"FAIL: no session logs in {log_folder}")
    newest = max(files, key=os.path.getmtime)
    return os.path.splitext(os.path.basename(newest))[0], newest


def stop_hook_blocks(log_folder, session_id):
    """Distinct attempt numbers seen in the session and its sub-agents (a block = one attempt)."""
    paths = [os.path.join(log_folder, f"{session_id}.jsonl")]
    paths += glob.glob(os.path.join(log_folder, session_id, "**", "*.jsonl"), recursive=True)
    seen = set()
    for path in paths:
        with open(path, encoding="utf-8") as f:
            for line in f:
                seen.update(ATTEMPT.findall(line))
    return len(seen)


def ci_facts(pr, task):
    """Agent pushes that ran CI on THIS pull request: until the first green one, and in total.

    Only commits of this PR count, so runs of other PRs that reused the branch name are ignored.
    """
    info = gh_json("pr", "view", str(pr), "--json", "headRefName,commits")
    commits = [c["oid"] for c in info["commits"]]
    if task == "T3" and commits:
        commits = commits[1:]  # the first commit is the planted change, made by the human
    mine = set(commits)
    runs = gh_json("run", "list", "--workflow", "pr.yml", "--branch", info["headRefName"], "--limit", "100",
                   "--json", "headSha,event,conclusion,databaseId,createdAt")
    runs = sorted((r for r in runs if r["event"] == "pull_request" and r["headSha"] in mine),
                  key=lambda r: r["createdAt"])
    shas = []
    for run in runs:
        if run["headSha"] not in shas:
            shas.append(run["headSha"])

    def passed(sha):
        same = [r for r in runs if r["headSha"] == sha]
        return bool(same) and same[-1]["conclusion"] == "success"

    green = [i for i, sha in enumerate(shas, start=1) if passed(sha)]
    until_green = green[0] if green else len(shas)
    first_ok = "yes" if shas and passed(shas[0]) else "no"
    checks = subprocess.run(["gh", "pr", "checks", str(pr)], capture_output=True, text=True)
    return until_green, len(shas), first_ok, checks.returncode == 0, info["headRefName"]


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", required=True, choices=["baseline", "harness"])
    parser.add_argument("--task", required=True, choices=["T1", "T2", "T3", "T4"])
    parser.add_argument("--run", required=True, type=int, choices=[1, 2])
    parser.add_argument("--pr", required=True, type=int)
    parser.add_argument("--root", default=os.path.expanduser("~/code"))
    args = parser.parse_args(argv)

    copy = os.path.realpath(os.path.join(args.root, f"aigt-bench-{args.config}"))
    log_folder = usage.log_dir(copy, os.path.expanduser("~"))
    if log_folder is None:
        raise SystemExit(f"FAIL: no Claude Code logs for {copy}")
    session_id, _ = newest_session(log_folder)
    blocks = stop_hook_blocks(log_folder, session_id)
    until_green, total, first_ok, all_pass, branch = ci_facts(args.pr, args.task)

    run_id = f"{args.task}-{args.config[0]}{args.run}"
    print(f"session: {session_id} (newest log in {log_folder})")
    print(f"branch: {branch}   pushes until CI green: {until_green}   pushes in total: {total}   "
          f"first push passed CI: {first_ok}   all checks pass now: {'yes' if all_pass else 'no'}")
    print(f"stop-hook blocks: {blocks}")
    print("Draft row (replace each ? after checking the task criteria and the session):")
    note = f"{total} pushes in total" if total != until_green else ""
    print(f"{run_id},{args.task},{args.config},{args.run},{session_id},{args.pr},{date.today()},?,"
          f"{first_ok},{until_green},{blocks},?,{note}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
