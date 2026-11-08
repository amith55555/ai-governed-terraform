"""The `plan_summary` tool: summarise the CI plan of a pull request."""
import json
import os
import re
import shutil
import tempfile
from pathlib import Path

from checks import run_command, safe_env
from output import ANSI, MAX_CHANGES, MAX_FINDINGS, respond

ENVS = ("dev", "prod")
LEVELS = ("low", "medium", "high")
CHANGE_KINDS = ("add", "change", "replace", "destroy", "forget", "other")
GH_TIMEOUT = 60
MAX_ARTIFACT_BYTES = 1_000_000
MAX_PR = 1_000_000

# A Terraform address, including for_each keys. No spaces: a sentence hidden in a key is rejected.
ADDRESS = re.compile(r'^[A-Za-z0-9_.\-\[\]"]{1,200}$')
SHA = re.compile(r"^[0-9a-f]{40}$")
POLICY_LINE = re.compile(r"^Plan \((dev|prod)\)\t[^\t]*\t\S+\s+FAIL - \S+ - (\S+) - (.+)$")


class Unusable(Exception):
    """The CI data is missing or not in the shape we expect."""


# ---------- the only gh commands this tool can run ----------

def gh_env():
    env = safe_env()
    if "GH_TOKEN" in os.environ:  # the agent's limited token from `make agent`
        env["GH_TOKEN"] = os.environ["GH_TOKEN"]
    return env


def run_gh(argv):
    return run_command(["gh", *argv], gh_env(), timeout=GH_TIMEOUT)


def number(value):
    if type(value) is not int or not 0 < value < 10**12:
        raise ValueError("not a valid id")
    return str(value)


def cmd_pr_head(pr):
    return ["pr", "view", number(pr), "--json", "headRefOid,state"]


def cmd_runs(sha):
    if not SHA.match(sha):
        raise ValueError("not a commit sha")
    return ["run", "list", "--workflow", "pr.yml", "--commit", sha, "--limit", "10",
            "--json", "databaseId,status,conclusion,event,headSha"]


def cmd_download(run_id, env, folder):
    if env not in ENVS:
        raise ValueError("unknown env")
    return ["run", "download", number(run_id), "-n", f"risk-{env}", "-D", folder]


def cmd_failed_log(run_id):
    return ["run", "view", number(run_id), "--log-failed"]


# ---------- reading CI data ----------

def gh_json(gh, argv):
    code, text = gh(argv)
    if code != 0:
        raise Unusable("GitHub request failed (is the agent token valid?)")
    try:
        return json.loads(text)
    except ValueError:
        raise Unusable("GitHub returned something that is not JSON")


def latest_run(runs, sha):
    runs = [r for r in runs if isinstance(r, dict) and r.get("event") == "pull_request"
            and r.get("headSha") == sha and type(r.get("databaseId")) is int]
    return max(runs, key=lambda r: r["databaseId"], default=None)


def check_risk(data):
    """Accept only the exact shape risk_gate.py writes. Anything else is refused, not repaired."""
    if not isinstance(data, dict) or data.get("level") not in LEVELS:
        raise Unusable("risk report has no valid level")
    counts = data.get("counts")
    if not isinstance(counts, dict) or set(counts) != set(CHANGE_KINDS) \
            or not all(type(v) is int and v >= 0 for v in counts.values()):
        raise Unusable("risk report has no valid counts (CI older than step 1?)")
    changes, reasons = [], []
    for item in data.get("changes", []) if isinstance(data.get("changes"), list) else []:
        if not isinstance(item, dict) or item.get("action") not in CHANGE_KINDS:
            raise Unusable("risk report has an invalid change")
        address = item.get("address")
        changes.append({"address": address if isinstance(address, str) and ADDRESS.match(address)
                        else "<invalid address>", "action": item["action"]})
    for item in data.get("reasons", []) if isinstance(data.get("reasons"), list) else []:
        if not isinstance(item, dict) or item.get("level") not in LEVELS:
            raise Unusable("risk report has an invalid reason")
        address = item.get("address")
        reasons.append({
            "level": item["level"],
            "address": address if isinstance(address, str) and ADDRESS.match(address) else "<invalid address>",
            "rule": str(item.get("rule", "")),
            "detail": str(item.get("detail", "")),
        })
    if sum(counts.values()) != len(changes):
        raise Unusable("risk report counts and changes disagree")
    return {"level": data["level"], "counts": counts, "changes": changes, "reasons": reasons}


def download_risk(gh, run_id, env):
    """Returns the checked report, or None if CI made no report for this env."""
    folder = tempfile.mkdtemp(prefix="tf-check-")
    try:
        code, _ = gh(cmd_download(run_id, env, folder))
        if code != 0:
            return None
        path = Path(folder) / "risk.json"
        if not path.is_file() or path.is_symlink() or path.stat().st_size > MAX_ARTIFACT_BYTES:
            raise Unusable(f"risk-{env} artifact is not a plain risk.json")
        try:
            return check_risk(json.loads(path.read_text(encoding="utf-8")))
        except ValueError:
            raise Unusable(f"risk-{env} artifact is not valid JSON")
    finally:
        shutil.rmtree(folder, ignore_errors=True)


def policy_failures(gh, run_id, envs):
    code, text = gh(cmd_failed_log(run_id))
    if code != 0:
        return []
    found = []
    for line in ANSI.sub("", text).splitlines():
        match = POLICY_LINE.match(line.rstrip())
        if match and match.group(1) in envs:
            env, rule, message = match.groups()
            found.append({"env": env, "rule": rule, "message": message})
    return found


# ---------- the tool ----------

def summarize(pr, env="all", gh=run_gh):
    tool = "plan_summary"
    if type(pr) is not int or not 0 < pr < MAX_PR:
        return respond(tool, "error", reason="pr must be a pull request number")
    if env not in ("dev", "prod", "all"):
        return respond(tool, "error", reason="env must be dev, prod or all")
    envs = ENVS if env == "all" else (env,)
    try:
        head = gh_json(gh, cmd_pr_head(pr))
        sha = head.get("headRefOid", "") if isinstance(head, dict) else ""
        if not isinstance(sha, str) or not SHA.match(sha):
            raise Unusable("pull request has no head commit")
        base = {"pr": pr, "commit": sha[:7]}

        runs = gh_json(gh, cmd_runs(sha))
        run = latest_run(runs if isinstance(runs, list) else [], sha)
        if run is None:
            return respond(tool, "pending", reason="CI has not started for the latest commit", **base)
        base["run"] = run["databaseId"]
        if run.get("status") != "completed":
            return respond(tool, "pending", reason="CI is still running for the latest commit", **base)

        reports = {name: download_risk(gh, run["databaseId"], name) for name in envs}
        missing = [name for name, report in reports.items() if report is None]
        policy = policy_failures(gh, run["databaseId"], missing) if missing else []

        changes = [{"env": name, **item} for name, r in reports.items() if r for item in r["changes"]]
        reasons = [{"env": name, **item} for name, r in reports.items() if r for item in r["reasons"]]
        levels = [r["level"] for r in reports.values() if r]
        fields = dict(
            base,
            level=max(levels, key=LEVELS.index) if levels and not missing else "unknown",
            counts={name: r["counts"] for name, r in reports.items() if r},
            missing=missing,
        )
        lists = {"reasons": (reasons, MAX_FINDINGS), "changes": (changes, MAX_CHANGES),
                 "policy": (policy, MAX_FINDINGS)}
        if policy:
            status = "policy_failed"
        elif missing:
            status = "no_plan"
            fields["reason"] = "CI produced no plan for these envs (failed before the plan, or artifacts expired)"
        else:
            status = "ok"
        return respond(tool, status, lists=lists, **fields)
    except (Unusable, ValueError) as exc:
        return respond(tool, "error", reason=str(exc))
