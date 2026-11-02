#!/usr/bin/env bash

set -euo pipefail

TOKEN_FILE="$HOME/.config/aigt-agent/token"

if [ ! -s "$TOKEN_FILE" ]; then
  echo "FAIL: no agent token in $TOKEN_FILE"
  exit 1
fi
if [ "$(stat -c %a "$TOKEN_FILE")" != "600" ]; then
  echo "FAIL: $TOKEN_FILE must be readable only by you (chmod 600 $TOKEN_FILE)"
  exit 1
fi

for profile in tfp-admin tfp-readonly; do
  if aws sts get-caller-identity --profile "$profile" > /dev/null 2>&1; then
    echo "FAIL: an AWS session is active (profile $profile). Run: aws sso logout"
    exit 1
  fi
done

claude_path="$(command -v claude || true)"
case "$claude_path" in
  "" | /mnt/*)
    echo "FAIL: use the Linux build of Claude Code, not the Windows one (found: ${claude_path:-nothing})"
    exit 1
    ;;
esac

GH_TOKEN="$(cat "$TOKEN_FILE")"
export GH_TOKEN

# git push uses the agent token too (through gh), never your own saved login.
export GIT_CONFIG_COUNT=2
export GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=""
export GIT_CONFIG_KEY_1=credential.helper GIT_CONFIG_VALUE_1="!gh auth git-credential"

echo "Agent session: GitHub as $(gh api user --jq .login) with the limited agent token; no AWS session."
cd "$(git rev-parse --show-toplevel)"
exec claude "$@"
