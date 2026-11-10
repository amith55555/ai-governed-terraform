#!/usr/bin/env bash
# Demo: what happens when the agent tries something. Runs the real pre-tool guard and
# risk gate from this repo on fixed inputs, so the output is the same every time.
# No AWS, no network, nothing is changed. Run from anywhere in the repo:
#   bash docs/demo/demo.sh
# docs/demo/demo.gif shows this output, rendered by docs/demo/render.py (needs Pillow).

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export CLAUDE_PROJECT_DIR="$PWD"
PAUSE="${DEMO_PAUSE:-0}"

try() {  # $1 = what the agent tries, $2 = tool name, $3 = tool input as JSON
  printf '\n$ agent: %s\n' "$1"
  sleep "$PAUSE"
  local call="{\"tool_name\": \"$2\", \"tool_input\": $3, \"cwd\": \"$PWD\"}"
  if out=$(printf '%s' "$call" | python3 -I .claude/hooks/pre_tool_guard.py 2>&1); then
    printf '  allowed\n'
  else
    printf '  %s\n' "$out"
  fi
}

echo "== Pre-tool guard: every tool call is checked before it runs"
try "aws s3 ls" Bash '{"command": "aws s3 ls"}'
try "terraform apply" Bash '{"command": "terraform apply"}'
try "read ~/.aws/credentials" Read '{"file_path": "~/.aws/credentials"}'
try "edit the CI workflow" Write '{"file_path": ".github/workflows/pr.yml"}'
try "git push --force" Bash '{"command": "git push --force"}'
try "plan_summary with pr \"35; ls\"" mcp__tf-check__plan_summary '{"pr": "35; ls"}'
try "edit the alarms module" Write '{"file_path": "terraform/modules/alarms/main.tf"}'
try "make check" Bash '{"command": "make check"}'

printf '\n== Risk gate in CI: a plan that renames the DynamoDB table\n'
sleep "$PAUSE"
plan=$(mktemp)
trap 'rm -f "$plan"' EXIT
cat > "$plan" <<'JSON'
{"resource_changes": [{"address": "module.table.aws_dynamodb_table.this", "mode": "managed",
  "type": "aws_dynamodb_table", "change": {"actions": ["delete", "create"],
  "before": {"name": "aigt-dev-items"}, "after": {"name": "aigt-dev-orders"}}}]}
JSON
python3 -I risk/risk_gate.py "$plan" 2>/dev/null | python3 -I -c '
import json, sys
result = json.load(sys.stdin)
level = result["level"]
print("  risk level: " + level)
for r in result["reasons"]:
    print("  " + r["address"] + ": " + r["detail"])
if level == "high":
    print("  -> waits in risk-approval until the owner approves")
'
