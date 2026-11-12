#!/usr/bin/env bash
# Runs a whole batch, one run after another. Keep this terminal open and the laptop awake.
#   schedule.sh selftest  reference solutions instead of the agent; judges must say pass/fail correctly
#   schedule.sh pilot     one real agent run to test the plumbing (discarded)
#   schedule.sh v2        the 12 benchmark runs; skips runs already recorded, retries runs cut by the usage limit
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

one() {  # TASK CONFIG RUN_ID AGENT; retries a run that hit the usage limit
  for attempt in 1 2 3 4 5; do
    bash "$HERE/run.sh" "$@"
    case $? in
      0) return 0 ;;
      3) echo "usage limit: waiting 60 minutes (attempt $attempt)"; sleep 3600 ;;
      *) echo "run $3 stopped with an error: see $HERE/runs/$3/run.log"; return 1 ;;
    esac
  done
}

case "${1:-}" in
  selftest)
    export TAG=origin/main RESULTS_NAME=selftest
    rm -f "$HERE/results/selftest.csv"
    for task in C1 C2 C3; do
      for kind in good bad; do
        one "$task" harness "st-$task-$kind" "ref-$kind" || exit 1
      done
    done
    echo; echo "== self-test (good must be yes, bad must be no)"
    cut -d, -f1,8,9,10,20 "$HERE/results/selftest.csv" | column -s, -t
    ;;
  pilot)
    export TAG=origin/main RESULTS_NAME=pilot
    one C2 harness "pilot-C2" claude
    cut -d, -f1,7,8,9,10,12,13,15,16,20 "$HERE/results/pilot.csv" | column -s, -t
    ;;
  v2)
    order="C1:baseline:C1-b1 C1:harness:C1-h1 C2:harness:C2-h1 C2:baseline:C2-b1 C3:baseline:C3-b1 C3:harness:C3-h1
           C1:harness:C1-h2 C1:baseline:C1-b2 C2:baseline:C2-b2 C2:harness:C2-h2 C3:harness:C3-h2 C3:baseline:C3-b2"
    for item in $order; do
      IFS=: read -r task config id <<< "$item"
      if grep -q "^$id," "$HERE/results/v2.csv" 2>/dev/null; then echo "$id already recorded, skipping"; continue; fi
      one "$task" "$config" "$id" claude || exit 1
      sleep 120
    done
    cut -d, -f1,7,8,9,10,12,13,15,16,20 "$HERE/results/v2.csv" | column -s, -t
    ;;
  *) echo "usage: schedule.sh selftest|pilot|v2"; exit 1 ;;
esac
