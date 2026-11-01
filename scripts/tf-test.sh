#!/usr/bin/env bash

set -euo pipefail

mapfile -t dirs < <(find terraform/modules -path '*/tests/*.tftest.hcl' -printf '%h\n' | xargs -r -n1 dirname | sort -u)

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "FAIL: no module tests found, nothing was tested."
  exit 1
fi

for dir in "${dirs[@]}"; do
  echo "== terraform test: $dir"
  terraform -chdir="$dir" init -backend=false -input=false > /dev/null
  terraform -chdir="$dir" test
done
