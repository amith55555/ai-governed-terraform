# ADR 0006: The agent has its own limited GitHub token

- Status: Accepted
- Date: 2026-11-02

## Context

Until now the agent ran with the owner's `gh` login, which can approve
environments, merge pull requests and edit rulesets. Every approval gate
(ADR 0003, ADR 0004) was only as strong as the hook that blocked those
commands.

## Decision

- The agent uses a fine-grained token, limited to this repository:
  Contents read/write, Pull requests read/write, Actions read-only, Commit
  statuses read-only, nothing else. It expires after 30 days.
- `make agent` (`scripts/agent-session.sh`) starts Claude Code with that
  token for `gh` and `git push`, and refuses to start if an AWS session is
  active, the token file is readable by others, or the Windows build of
  Claude Code would run.
- The guard blocks reading the token file and `/proc/` (the token is in the
  process environment).

Verified: the token cannot read rulesets or create environments (HTTP 403),
and GitHub refuses its push of a change to `.github/workflows/`.

## Known limits

- Same account: commits and PRs still show the owner as author, so GitHub
  cannot enforce CODEOWNERS against the agent. Upgrade path: a separate
  machine account or a GitHub App.
- The owner's own `gh` login is still on the machine. The guard blocks
  `gh auth` and reading `~/.config/gh`; a separate Linux user or container
  for the agent would remove it entirely.
- The token must be rotated every 30 days.
