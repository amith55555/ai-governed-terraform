#!/usr/bin/env bash

set -euo pipefail

CONFIG="policies/checkov/config.yml"
RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT
fail=0

echo "== Guard 1: no inline Checkov skips in Terraform"
if grep -rniE --exclude-dir=.terraform 'checkov:skip' terraform/; then
  echo "FAIL: inline skips are not allowed. Add the rule to $CONFIG with a reason in the ADR."
  fail=1
else
  echo "ok"
fi

echo "== Guard 2: no other Checkov config files"
others="$(find . -path ./.git -prune -o \( -iname '.checkov.yml' -o -iname '.checkov.yaml' \) -print)"
if [ -n "$others" ]; then
  echo "$others"
  echo "FAIL: only $CONFIG may configure Checkov."
  fail=1
else
  echo "ok"
fi

echo "== Checkov"
ckv=0
checkov -d terraform --config-file "$CONFIG" -o json > "$RESULTS" || ckv=$?

passed="$(jq '[.] | flatten | map(.summary.passed) | add' "$RESULTS")"
failed="$(jq '[.] | flatten | map(.summary.failed) | add' "$RESULTS")"
parse_errors="$(jq '[.] | flatten | map(.summary.parsing_errors) | add' "$RESULTS")"
echo "passed=$passed failed=$failed parsing_errors=$parse_errors"

jq -r '[.] | flatten | .[].results.failed_checks[]?
  | "  \(.check_id)  \(.file_path):\(.file_line_range[0])  \(.resource)\n      \(.check_name)"' "$RESULTS"

if [ "$ckv" -ne 0 ]; then
  echo "FAIL: Checkov found problems (exit code $ckv)."
  fail=1
fi

echo "== Guard 3: Checkov could read every file"
if [ "$parse_errors" -ne 0 ]; then
  echo "FAIL: $parse_errors file(s) could not be parsed, so they were not scanned."
  fail=1
else
  echo "ok"
fi

echo "== Guard 4: Checkov actually checked something"
if [ "$passed" -eq 0 ]; then
  echo "FAIL: 0 checks passed. The scan probably ran on nothing."
  fail=1
else
  echo "ok"
fi

if [ "$fail" -ne 0 ]; then
  echo "SCAN FAILED"
  exit 1
fi
echo "SCAN PASSED"
