# Settings for benchmark v2. Sourced by run.sh and schedule.sh.
MAIN="$HOME/code/ai-governed-terraform"   # your repo (judging, closing PRs: your own gh login)
BENCH_ROOT="$HOME/code"                    # where bench-setup keeps the copies
TAG="${TAG:-bench-base-v2}"                # start of every run; the self-test uses origin/main
CAP_MINUTES=45                             # per run, then the run counts as failed
CAP_USD=5                                  # per run, Claude Code's own cost estimate
CI_WAIT_MINUTES=30
FIXED_REPLY="Do what you think is best and open a pull request."
TOKEN_FILE="$HOME/.config/aigt-agent/token"
