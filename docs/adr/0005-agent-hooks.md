# ADR 0005: Agent hooks enforce the rules locally

- Status: Accepted
- Date: 2026-11-01
- Tool: Claude Code 2.1.165

## Context

AGENTS.md asks; it cannot enforce. An agent can ignore, misread or be
tricked out of any written rule. Claude Code runs hooks itself, so the agent
cannot skip them.

## Decision

Two hooks, configured in `.claude/settings.json`, written in plain Python
(stdlib only) and run with `python3 -I`:

- **Pre-tool guard** (`pre_tool_guard.py`), before Bash, Write, Edit,
  MultiEdit, NotebookEdit, Read, Grep and Glob:
  - Commands are an **allowlist**: safe `make` targets, safe `git`
    subcommands, read-only `gh` plus `gh pr create`, `terraform fmt`,
    read-only tools. Everything else is blocked.
  - No agent-written code runs locally: no `python3`, `bash`, `./script`,
    `env`, `xargs`, `make` options or `make` outside the repo root, no `$`,
    backticks, subshells or here-documents.
  - Paths are resolved for real (`~`, `../`, symlinks, `cd`) before the
    protected-path and secret-file checks.
  - Fails closed: any error blocks.
- **Completion hook** (`stop_require_check.py`), when the agent says it is
  done: runs `make check` if anything changed; on failure the agent must
  continue and sees the last 40 lines. At most 3 attempts per session, and
  the same error twice stops early, with a warning to the owner. It fails
  visibly, not closed: a blocking error here could loop forever, and CI
  rechecks everything.

Tested by `make hook-test`: 74 attack commands that must be blocked, 25
normal commands that must work, file-tool cases, loop limits, and a test
that the protected-path lists in the hook, `guard.yml` and CODEOWNERS agree.

Config files that tools load automatically (`GNUmakefile`, mise files,
`.gitleaks.toml`, `.gitleaksignore`, `conftest.toml`) are protected paths,
in CI too.

## Known limits

- **The completion hook cannot tell whose changes it checks.** Any
  uncommitted change makes it run, so a read-only task can be blocked by the
  owner's own work in progress (seen in the W2.7 live test). Possible fix:
  record the git state at session start and only check what changed since.
- **Fixed after the W2.7 live test:** "same error twice" never fired, because
  gitleaks prints timestamps and durations. The failure fingerprint now
  ignores numbers, and a test covers it.
- **A hook that cannot start fails open.** Claude Code treats any exit code
  other than 2 as a non-blocking error and runs the tool. Found in the live
  test: the Windows build of Claude Code had no `python3`, every hook failed,
  and the agent read a (fake) secret file. Fixed: the guard's command ends
  with `|| exit 2`, and a test checks it.
- **Claude Code must run inside WSL/Linux**, where the hooks' `python3`
  exists. The Windows build started from a WSL terminal does not qualify.
- **Identity:** allowed commands (`git push`, `gh pr create`) still use the
  owner's credentials. W2.8 gives the agent its own limited token.
- **Owner's AWS session:** the guard blocks AWS commands, but the owner logs
  out of AWS before agent sessions as a second layer.
- **Tool coverage:** only the listed tools are checked. MCP tools (week 3)
  must be read-only by design and added to the matcher.
- **Local only:** a session started without these project settings has no
  hooks. CI is the final authority and rechecks everything.
- **False positives:** `$` is blocked even inside commit messages, and a
  message ending in `.tfvars` is blocked. The agent rewrites the command.
- **Cost:** the completion hook runs `make check` (about 1-2 minutes) each
  time the agent finishes with changes.
