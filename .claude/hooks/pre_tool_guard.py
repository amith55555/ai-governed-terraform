#!/usr/bin/env python3
"""PreToolUse guard for Claude Code.

Reads one tool call as JSON on stdin and decides with fixed rules:
exit 0 = allow, exit 2 = block (the reason on stderr is shown to the agent).
Any unexpected error also blocks (fail closed).
Rules: AGENTS.md F1-F7. Design and known limits: docs/adr/0005-agent-hooks.md.
"""
import json
import os
import re
import shlex
import sys

# Same list as .github/workflows/guard.yml, plus .git/ (git hooks and config).
# Includes config files that tools load automatically (make, mise, gitleaks, conftest).
PROTECTED = re.compile(
    r"^(\.github|policies|scripts|risk|terraform/bootstrap|\.claude|mcp-servers|\.git|\.config|mise)(/|$)"
    r"|^(Makefile|GNUmakefile|makefile|mise\.toml|\.mise\.toml|mise\.local\.toml|\.mise\.local\.toml"
    r"|\.tool-versions|\.terraform-version|\.python-version|\.pre-commit-config\.yaml|\.tflint\.hcl"
    r"|\.gitleaks\.toml|\.gitleaksignore|conftest\.toml|AGENTS\.md|CLAUDE\.md|\.mcp\.json)$"
)

# Credentials and private values: never read or write.
SENSITIVE = re.compile(
    r"(^|/)(\.aws|\.ssh|\.gnupg|\.docker|\.kube)(/|$)"
    r"|(^|/)\.config/gh(/|$)"
    r"|(^|/)\.env(\.|$)"
    r"|\.tfvars(\.json)?$"
    r"|\.tfstate(\.|$)"
    r"|(^|/)(\.terraformrc|terraform\.rc)$"
    r"|(^|/)\.config/aigt-agent(/|$)"
    r"|^/proc/"
)

# Files that would make CI skip checks (ADR 0001, ADR 0002).
FORBIDDEN_FILES = re.compile(r"(\.tf\.json|(^|/)\.checkov\.ya?ml)$")

READ_ONLY = {
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "diff", "echo", "printf", "pwd",
    "sort", "uniq", "cut", "tr", "jq", "tree", "file", "stat", "basename", "dirname",
    "true", "which", "date",
}
WRITERS = {"mkdir", "touch", "cp", "mv", "rm", "tee"}
FIND_FORBIDDEN = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}

MAKE_TARGETS = {
    "help", "check", "static", "scan", "secrets", "policy", "plan-policy",
    "risk", "risk-test", "test", "agents-md", "hook-test",
}
MAKE_INFRA_TARGETS = {"up", "down", "plan"}

TERRAFORM_ALLOWED = {"fmt", "version"}
TERRAFORM_STATE_CHANGING = {"apply", "destroy", "import", "state", "taint", "untaint", "force-unlock"}

GIT_ALLOWED = {
    "status", "diff", "log", "show", "add", "commit", "switch", "checkout", "restore",
    "branch", "stash", "fetch", "pull", "push", "rev-parse", "ls-files", "blame",
    "merge-base", "revert", "reset", "rm", "mv",
}
GIT_PATH_WRITERS = {"checkout", "restore", "reset", "rm", "mv"}

GH_ALLOWED = {
    ("pr", "create"), ("pr", "view"), ("pr", "checks"), ("pr", "diff"), ("pr", "list"),
    ("pr", "status"), ("run", "view"), ("run", "list"), ("run", "watch"),
    ("issue", "view"), ("issue", "list"), ("repo", "view"),
}

PROGRAM_REASONS = {
    "aws": "AWS commands are forbidden (AGENTS.md F2)",
    "sudo": "sudo is forbidden",
}

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
READ_TOOLS = {"Read", "Grep", "Glob"}

PUNCTUATION = "();<>|&\n"


class Blocked(Exception):
    pass


# ---------- paths ----------

def resolve(path, cwd):
    return os.path.realpath(os.path.join(cwd, os.path.expanduser(path)))


def repo_relative(real, root):
    rel = os.path.relpath(real, root)
    if rel == ".." or rel.startswith("../"):
        return None
    return rel


def check_read(path, cwd):
    if SENSITIVE.search(path) or SENSITIVE.search(resolve(path, cwd)):
        raise Blocked(f"'{path}' holds credentials or private values")


def check_write(path, cwd, root):
    if path == "/dev/null":
        return
    if re.search(r"[*?\[\]{}]", path):
        raise Blocked(f"wildcards are not allowed in a path that is written or deleted: '{path}'")
    check_read(path, cwd)
    rel = repo_relative(resolve(path, cwd), root)
    if rel is None:
        raise Blocked(f"'{path}' is outside the repo")
    if rel == ".":
        raise Blocked("changing the whole repo at once is not allowed")
    if PROTECTED.search(rel):
        raise Blocked(f"'{rel}' is a protected path (AGENTS.md F3)")
    if FORBIDDEN_FILES.search(rel):
        raise Blocked(f"'{rel}' would make CI skip checks (*.tf.json, .checkov.yml)")


# ---------- shell commands ----------

def tokenize(command):
    if "$" in command or "`" in command:
        raise Blocked("'$' and backticks are not allowed: write the command out literally")
    lexer = shlex.shlex(command, posix=True, punctuation_chars=PUNCTUATION)
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    try:
        return list(lexer)
    except ValueError as exc:
        raise Blocked(f"could not parse the command ({exc})")


def split_segments(tokens):
    """Split tokens into simple commands. Returns [(words, [(operator, target)])]."""
    segments, words, redirects = [], [], []
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if tok and set(tok) <= set(PUNCTUATION):
            if "(" in tok or ")" in tok:
                raise Blocked("subshells and parentheses are not allowed")
            if "<<" in tok:
                raise Blocked("here-documents (<<) are not allowed")
            if "<" in tok or ">" in tok:
                if i + 1 >= len(tokens):
                    raise Blocked("redirection without a target")
                if words and words[-1].isdigit():
                    words.pop()  # the "2" in "2>&1" is a file descriptor, not an argument
                redirects.append((tok, tokens[i + 1]))
                i += 2
                continue
            segments.append((words, redirects))
            words, redirects = [], []
            i += 1
            continue
        words.append(tok)
        i += 1
    segments.append((words, redirects))
    return segments


def check_bash(command, cwd, root):
    if "--no-verify" in command:
        raise Blocked("--no-verify is forbidden (AGENTS.md F5)")
    state = {"cwd": cwd}
    for words, redirects in split_segments(tokenize(command)):
        for operator, target in redirects:
            if operator.endswith("&") and target.isdigit():
                continue  # 2>&1
            if ">" in operator:
                check_write(target, state["cwd"], root)
            else:
                check_read(target, state["cwd"])
        if words:
            check_simple_command(words, state, root)


def check_simple_command(words, state, root):
    cwd = state["cwd"]
    prog, args = words[0], words[1:]
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", prog):
        raise Blocked("setting environment variables in a command is not allowed")
    if "/" in prog:
        raise Blocked(f"run programs by name, not by path: '{prog}'")
    for arg in args:
        check_read(arg, cwd)
    if prog in PROGRAM_REASONS:
        raise Blocked(PROGRAM_REASONS[prog])

    if prog == "cd":
        target = resolve(args[0] if args else "~", cwd)
        if repo_relative(target, root) is None:
            raise Blocked("cd outside the repo is not allowed")
        state["cwd"] = target
    elif prog in READ_ONLY:
        pass
    elif prog == "find":
        if any(a in FIND_FORBIDDEN for a in args):
            raise Blocked("find -exec and -delete are not allowed")
    elif prog in WRITERS:
        for a in args:
            if a.startswith("-"):
                if "=" in a:
                    check_write(a.split("=", 1)[1], cwd, root)
                continue
            check_write(a, cwd, root)
    elif prog == "git":
        check_git(args, cwd, root)
    elif prog == "gh":
        check_gh(args)
    elif prog == "make":
        check_make(args, cwd, root)
    elif prog == "terraform":
        check_terraform(args)
    else:
        raise Blocked(f"'{prog}' is not on the allowed command list (use the make targets)")


def check_git(args, cwd, root):
    if not args or args[0].startswith("-"):
        raise Blocked("git options before the subcommand are not allowed (git -c can run commands)")
    sub, rest = args[0], args[1:]
    if sub not in GIT_ALLOWED:
        raise Blocked(f"'git {sub}' is not allowed")
    short_flags = [a[1:] for a in rest if a.startswith("-") and not a.startswith("--")]
    if sub == "commit" and any("n" in f for f in short_flags):
        raise Blocked("git commit -n skips hooks (AGENTS.md F5)")
    if sub == "push":
        if any(a.startswith(("--force", "--delete", "--mirror", "--all", "--tags", "--prune")) for a in rest):
            raise Blocked("force, delete and mirror pushes are not allowed")
        if any(c in f for f in short_flags for c in "fd"):
            raise Blocked("force and delete pushes are not allowed")
        if any(not a.startswith("-") and (":" in a or a in ("main", "HEAD")) for a in rest):
            raise Blocked("push your own branch by name only: never main, HEAD or refspecs")
    if sub in GIT_PATH_WRITERS:
        paths = rest[rest.index("--") + 1:] if "--" in rest else [a for a in rest if not a.startswith("-")]
        for p in paths:
            check_write(p, cwd, root)


def check_gh(args):
    if len(args) < 2 or (args[0], args[1]) not in GH_ALLOWED:
        raise Blocked("only read-only gh commands and 'gh pr create' are allowed (AGENTS.md F4)")


def check_make(args, cwd, root):
    if os.path.realpath(cwd) != root:
        raise Blocked("run make from the repo root only")
    for a in args:
        if a.startswith("-"):
            raise Blocked("make options are not allowed (-f or -C could load another Makefile)")
        if "=" in a:
            key, value = a.split("=", 1)
            if key == "OUT":
                check_write(value, cwd, root)
            elif key != "PLAN":
                raise Blocked(f"make variable '{key}' is not allowed")
            continue
        if a in MAKE_INFRA_TARGETS:
            raise Blocked(f"'make {a}' uses AWS and real infrastructure (AGENTS.md F1, F2)")
        if a not in MAKE_TARGETS:
            raise Blocked(f"'make {a}' is not an allowed target")


def check_terraform(args):
    sub_args = [a for a in args if not a.startswith("-chdir=")]
    sub = sub_args[0] if sub_args else ""
    if sub in TERRAFORM_STATE_CHANGING:
        raise Blocked(f"'terraform {sub}' changes real state: only CI may do that (AGENTS.md F1)")
    if sub not in TERRAFORM_ALLOWED:
        raise Blocked(f"'terraform {sub}' is not allowed: use make static / make test")


# ---------- entry points ----------

def check(payload, root):
    """Return None to allow, or the reason to block."""
    tool = payload.get("tool_name", "")
    data = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or root
    try:
        if tool == "Bash":
            check_bash(data.get("command", ""), cwd, root)
        elif tool in WRITE_TOOLS:
            path = data.get("file_path") or data.get("notebook_path")
            if not path:
                raise Blocked("no file path given")
            check_write(path, cwd, root)
        elif tool in READ_TOOLS:
            for key in ("file_path", "path", "pattern", "glob"):
                if data.get(key):
                    check_read(data[key], cwd)
    except Blocked as exc:
        return str(exc)
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        root = os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd())
        reason = check(payload, root)
    except Exception as exc:  # fail closed
        reason = f"guard error, blocked to be safe ({exc.__class__.__name__})"
    if reason:
        print(f"BLOCKED by pre-tool guard: {reason}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
