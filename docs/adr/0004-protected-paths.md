# ADR 0004: Protected paths need the owner's approval

- Status: Accepted (list updated in W3.6)
- Date: 2026-11-01, updated 2026-11-10

## Context

The checks are only as strong as the files that define them. An agent that
can edit `.github/workflows/pr.yml`, `policies/`, `scripts/` or the Makefile
can switch a check off, and a `pull_request` workflow runs the PR's own,
edited copy. CODEOWNERS cannot help on its own: GitHub never lets the author
of a PR approve it, and this repo has one maintainer whose identity the
agent also uses.

## Decision

- `.github/CODEOWNERS` lists the owner of every guardrail path.
- `.github/workflows/guard.yml` runs on `pull_request_target`, so the copy
  from `main` runs and a PR cannot weaken it. It never checks out PR code;
  it only lists changed files through the API (`pull-requests: read`).
- If any changed file (or the old name of a renamed file) matches a
  protected path, "Protected paths approval" waits in the
  `guardrail-approval` environment for the owner. If the API lists fewer
  files than the PR has, the PR is treated as protected.
- Both jobs are required checks. Every push needs a new approval.

Protected (W3.6; the source of truth is `PROTECTED` in `guard.yml`):

- Folders: `.github/`, `policies/`, `scripts/`, `risk/`, `terraform/bootstrap/`,
  `.claude/`, `mcp-servers/`, `benchmarks/`, `evals/`, `.config/`, `mise/`.
- Files: `docs/agent-log.md`, `Makefile`, `GNUmakefile`, `makefile`, the mise files
  (`mise.toml`, `.mise.toml`, `mise.local.toml`, `.mise.local.toml`),
  `.tool-versions`, `.terraform-version`, `.python-version`,
  `.pre-commit-config.yaml`, `.tflint.hcl`, `.gitleaks.toml`, `.gitleaksignore`,
  `conftest.toml`, `AGENTS.md`, `CLAUDE.md`, `.mcp.json`.
- The local guard also protects `.git/` (ADR 0005).

`benchmarks/` and `evals/` were added in week 3 so the agent cannot change the
tests it is measured with. `docs/agent-log.md` is protected so the agent cannot
edit the record of its own mistakes.

## Known weak spot

Approvals are only as strong as the identity that can approve. Claude Code
runs on the owner's laptop with the owner's `gh` login, which can approve
environments, merge PRs and edit rulesets. Before the first agent PR:

1. Agent hooks block `gh` commands that approve, merge or call admin APIs.
2. The agent uses its own fine-grained token, limited to pushing branches
   and opening pull requests.

## Consequences

- Changes to guardrails cost one extra click for the owner.
- The first PR that adds `guard.yml` cannot be protected by it: the
  workflow only exists after it is merged.
- The path list exists three times (`guard.yml`, CODEOWNERS and the local
  guard). `.claude/hooks/test_protected_lists.py` fails if they disagree.
