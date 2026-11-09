#!/usr/bin/env bash
# T4 judge: apply each mutation from benchmarks/tasks/T4-s3-bucket-tests.md to the s3_bucket
# module of a pull request, one at a time, and check that the module's tests FAIL each time.
#   bash benchmarks/mutation_t4.sh 51
# Works in a throwaway git worktree; never touches your folder. Needs terraform (mise).

set -euo pipefail

PR="${1:?usage: bash benchmarks/mutation_t4.sh PR_NUMBER}"
REPO="$(git rev-parse --show-toplevel)"
WORK="$(mktemp -d)/pr-$PR"
MOD="terraform/modules/s3_bucket"

git -C "$REPO" fetch -q origin "+refs/pull/$PR/head:refs/remotes/pr/$PR"
git -C "$REPO" worktree add -q --detach "$WORK" "pr/$PR"
trap 'git -C "$REPO" worktree remove --force "$WORK"' EXIT
cd "$WORK"

run_tests() {
  terraform -chdir="$MOD" init -backend=false -input=false > /dev/null 2>&1
  terraform -chdir="$MOD" test > /dev/null 2>&1
}

mutate() {
  case "$1" in
    1) sed -i 's/block_public_acls       = true/block_public_acls       = false/' "$MOD/main.tf" ;;
    2) sed -i '/"aws_s3_bucket_versioning"/,/^}/ s/status = "Enabled"/status = "Suspended"/' "$MOD/main.tf" ;;
    3) sed -i 's/sse_algorithm = "AES256"/sse_algorithm = "aws:kms"/' "$MOD/main.tf" ;;
    4) python3 -I - "$MOD/main.tf" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
new = re.sub(r'  statement \{\n    sid += "DenyInsecureTransport".*?\n  \}\n(?=\})', "", text, count=1, flags=re.S)
open(path, "w", encoding="utf-8").write(new)
PY
       ;;
    5) sed -i '0,/condition *= *can(regex/ s/condition *= *can(regex.*$/condition     = true/' "$MOD/variables.tf" ;;
  esac
}

NAMES=("" "block_public_acls = false" "versioning Suspended" "sse_algorithm aws:kms"
       "DenyInsecureTransport removed" "name validation = true")

echo "== Unmutated module: tests must pass"
if run_tests; then echo "ok"; else echo "FAIL: the PR's own tests fail without any mutation"; exit 1; fi

caught=0
for n in 1 2 3 4 5; do
  git checkout -q -- "$MOD"
  before="$(cat "$MOD/main.tf" "$MOD/variables.tf" | sha256sum)"
  mutate "$n"
  if [ "$(cat "$MOD/main.tf" "$MOD/variables.tf" | sha256sum)" = "$before" ]; then
    echo "mutation $n (${NAMES[$n]}): NOT APPLIED - the module text differs from main; judge by hand"
    continue
  fi
  if run_tests; then
    echo "mutation $n (${NAMES[$n]}): tests still pass  -> NOT caught"
  else
    echo "mutation $n (${NAMES[$n]}): tests fail        -> caught"
    caught=$((caught + 1))
  fi
done
echo "caught $caught of 5 (criterion 3 holds only at 5 of 5)"
