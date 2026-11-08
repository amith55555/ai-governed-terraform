#!/usr/bin/env bash

set -euo pipefail

TAG="${BENCH_TAG:-bench-base-v1}"  # BENCH_TAG only for a trial run before the tag exists
CONFIG="${1:-}"
HARNESS_FILES=(.claude AGENTS.md CLAUDE.md .mcp.json)

case "$CONFIG" in
  harness | baseline) ;;
  *) echo "usage: bash scripts/bench-setup.sh harness|baseline"; exit 1 ;;
esac

SOURCE="$(git rev-parse --show-toplevel)"
URL="$(git -C "$SOURCE" remote get-url origin)"
DIR="${BENCH_ROOT:-$HOME/code}/aigt-bench-$CONFIG"

if [ ! -d "$DIR/.git" ]; then
  echo "== Cloning into $DIR"
  git clone --quiet "$URL" "$DIR"
fi
cd "$DIR"

echo "== Resetting to $TAG"
git fetch --quiet --force --tags origin
mapfile -t skipped < <(git ls-files -v | awk '/^S /{print substr($0, 3)}')
if [ "${#skipped[@]}" -gt 0 ]; then
  git update-index --no-skip-worktree -- "${skipped[@]}"
fi
git reset --quiet --hard
git switch --quiet --detach "$TAG"
git clean -fdxq -e mcp-servers/tf-check/.venv
git for-each-ref --format='%(refname:short)' refs/heads | xargs -r git branch -q -D

if [ "$CONFIG" = "baseline" ]; then
  echo "== Hiding the agent config: ${HARNESS_FILES[*]}"
  mapfile -t files < <(git ls-files -- "${HARNESS_FILES[@]}")
  git update-index --skip-worktree -- "${files[@]}"
  rm -rf -- "${HARNESS_FILES[@]}"
  rm -rf mcp-servers/tf-check/.venv
else
  if [ ! -x mcp-servers/tf-check/.venv/bin/python ]; then
    echo "== Installing the tf-check server"
    make --no-print-directory mcp-install > /dev/null
  fi
fi

echo "== Checks"
fail=0
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  echo "FAIL: the copy is not clean"
  fail=1
fi
if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$TAG^{commit}")" ]; then
  echo "FAIL: not at $TAG"
  fail=1
fi
for f in "${HARNESS_FILES[@]}"; do
  if [ "$CONFIG" = "baseline" ] && [ -e "$f" ]; then echo "FAIL: $f still exists"; fail=1; fi
  if [ "$CONFIG" = "harness" ] && [ ! -e "$f" ]; then echo "FAIL: $f is missing"; fail=1; fi
done
[ "$fail" -eq 0 ] || exit 1

echo "ok: $CONFIG copy at $TAG ($(git rev-parse --short HEAD)), clean"
echo "Next: cd $DIR && make agent"
