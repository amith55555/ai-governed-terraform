#!/usr/bin/env bash
# One benchmark v2 run, start to end:
#   reset the copy -> (C3: plant the broken commit) -> agent or reference solution ->
#   wait for CI -> judge -> record one row -> close the PR.
# Usage: run.sh TASK CONFIG RUN_ID [claude|ref-good|ref-bad]
#   TASK = C1 | C2 | C3, CONFIG = baseline | harness (both run with the Agent tool off: no sub-agents)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/config.sh"
TASK="$1" CONFIG="$2" RUN_ID="$3" AGENT="${4:-claude}"
OUT="$HERE/runs/$RUN_ID"
RESULTS="$HERE/results/${RESULTS_NAME:-v2}.csv"
mkdir -p "$OUT" "$HERE/results"
log() { echo "[$(date +%H:%M:%S)] $RUN_ID: $*" | tee -a "$OUT/run.log"; }
die() { log "STOP: $*"; exit 2; }

case "$TASK:$CONFIG:$AGENT" in
  C[123]:baseline:claude|C[123]:harness:claude|C[123]:baseline:ref-*|C[123]:harness:ref-*) ;;
  *) die "usage: run.sh C1|C2|C3 baseline|harness RUN_ID [claude|ref-good|ref-bad]" ;;
esac

# Never start with an AWS session (the agent-session.sh launcher checks again).
for profile in tfp-admin tfp-readonly; do
  aws sts get-caller-identity --profile "$profile" > /dev/null 2>&1 && die "AWS session active ($profile): aws sso logout"
done

# 1. Reset the copy to the start tag. No sub-agents in v2: the Agent tool is turned off for
#    every run (--disallowedTools Agent), so all files stay in place and `make check` still passes.
COPY="$BENCH_ROOT/aigt-bench-$CONFIG"
(cd "$MAIN" && BENCH_TAG="$TAG" BENCH_ROOT="$BENCH_ROOT" bash scripts/bench-setup.sh "$CONFIG") >> "$OUT/run.log" 2>&1 \
  || die "bench-setup failed (see $OUT/run.log)"

# 2. C3 starts from a branch with 4 planted problems (one commit, made by the runner).
PLANTED=""
if [ "$TASK" = C3 ]; then
  (cd "$COPY" && git switch -q -c bench-start && git apply "$HERE/patches/C3-planted.patch" \
    && git -c core.hooksPath=/dev/null commit -qam "chore: tidy modules") >> "$OUT/run.log" 2>&1 || die "planting failed"
  PLANTED="$(git -C "$COPY" rev-parse HEAD)"
fi

agent_env() {  # same GitHub identity as `make agent`: the agent's limited token
  GH_TOKEN="$(cat "$TOKEN_FILE")" GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0="" \
  GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1="!gh auth git-credential" "$@"
}

find_pr() {  # the first PR opened since this run started
  (cd "$MAIN" && gh pr list --state open --limit 30 --json number,createdAt \
    --jq "[.[] | select(.createdAt >= \"$START\")] | sort_by(.createdAt) | .[0].number // empty")
}

claude_run() {  # $1 = output file, $2 = minutes left, rest = claude arguments
  local out="$1" minutes="$2"; shift 2
  (cd "$COPY" && DISABLE_AUTOUPDATER=1 timeout --signal=INT --kill-after=60 "${minutes}m" \
    bash scripts/agent-session.sh -p "$@" --disallowedTools Agent --permission-mode auto --permission-prompts none \
    --output-format json --max-budget-usd "$CAP_USD") > "$out" 2>> "$OUT/agent.err"
  echo $?
}

# 3. The agent (or a reference solution, for the self-test).
START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; T0=$(date +%s)
STATUS=ok FIXED=no
if [ "$AGENT" = claude ]; then
  log "agent starts ($CONFIG, $TASK)"
  rc=$(claude_run "$OUT/agent.json" "$CAP_MINUTES" "$(cat "$HERE/tasks/$TASK.txt")")
  [ "$rc" = 124 ] && STATUS=time-cap
  STATUS=$(python3 -I "$HERE/facts.py" status "$OUT/agent.json" "$STATUS")
  if [ "$STATUS" = ok ] && [ -z "$(find_pr)" ]; then
    left=$(( CAP_MINUTES - ($(date +%s) - T0) / 60 ))
    if [ "$left" -gt 1 ]; then
      log "no PR: sending the fixed reply once"
      FIXED=yes
      sid=$(python3 -I "$HERE/facts.py" session "$OUT/agent.json")
      rc=$(claude_run "$OUT/agent2.json" "$left" "$FIXED_REPLY" --resume "$sid")
      [ "$rc" = 124 ] && STATUS=time-cap
      STATUS=$(python3 -I "$HERE/facts.py" status "$OUT/agent2.json" "$STATUS")
    fi
  fi
else
  log "reference solution ($AGENT) instead of the agent"
  (cd "$COPY" && git switch -q -c "bench/$RUN_ID" && git apply "$HERE/refs/$TASK-${AGENT#ref-}.patch" && git add -A \
    && git -c core.hooksPath=/dev/null commit -qm "bench $RUN_ID: reference solution" \
    && agent_env git push -q -u origin "bench/$RUN_ID" \
    && agent_env gh pr create --title "bench $RUN_ID: reference solution (self-test, do not merge)" \
       --body "Benchmark v2 self-test: $AGENT for $TASK.") >> "$OUT/run.log" 2>&1 || die "reference PR failed"
fi
MINUTES=$(( ($(date +%s) - T0) / 60 ))

if [ "$STATUS" = limited ]; then
  log "hit the usage limit: run discarded, retry later"
  PR=$(find_pr); [ -n "$PR" ] && (cd "$MAIN" && gh pr close "$PR" --delete-branch > /dev/null 2>&1)
  exit 3
fi

# 4. Wait for CI (approval checks may wait forever: they are nobody's to click).
PR=$(find_pr)
VERDICT='{"success": false, "checks": {"pr_opened": false}}'
if [ -n "$PR" ]; then
  log "PR #$PR: waiting for CI"
  for _ in $(seq 1 $(( CI_WAIT_MINUTES * 2 ))); do
    sleep 30
    left=$(cd "$MAIN" && gh pr checks "$PR" --json name,bucket 2>/dev/null \
      | jq '([.[].name] | (any(test("Static checks")) and any(test("Protected paths"))) | not)
            or ([.[] | select(.bucket == "pending" and (.name | test("approval") | not))] | length > 0)')
    [ "$left" = false ] && break
  done
  # 5. Judge.
  VERDICT=$(python3 -I "$HERE/judge.py" "$TASK" "$PR" "$PLANTED" 2>> "$OUT/run.log") || VERDICT='{"success": false, "checks": {"judge_error": false}}'
fi
echo "$VERDICT" > "$OUT/verdict.json"

# 6. Record one row, then close the PR.
python3 -I "$HERE/facts.py" row "$RESULTS" "$RUN_ID" "$TASK" "$CONFIG" "$AGENT" "$COPY" "$OUT" "${PR:-}" \
  "$STATUS" "$FIXED" "$MINUTES" "$PLANTED" || log "could not write the row"
[ -n "${PR:-}" ] && (cd "$MAIN" && gh pr close "$PR" --delete-branch > /dev/null 2>&1) && log "PR #$PR closed"
log "done: $(jq -c '{success, checks}' "$OUT/verdict.json")"
