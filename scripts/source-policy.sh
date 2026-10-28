#!/usr/bin/env bash

set -euo pipefail

echo "== Guard: no .tf.json files"
json_files="$(find terraform -name '*.tf.json' -not -path '*/.terraform/*')"
if [ -n "$json_files" ]; then
  echo "$json_files"
  echo "FAIL: *.tf.json files are not allowed (they would skip the HCL policy check)."
  exit 1
fi
echo "ok"

echo "== Conftest: escape hatches in .tf files"
mapfile -t tf_files < <(find terraform -name '*.tf' -not -path '*/.terraform/*' | sort)
if [ "${#tf_files[@]}" -eq 0 ]; then
  echo "FAIL: no .tf files found, nothing was checked."
  exit 1
fi
conftest test --parser hcl2 --policy policies/hcl --all-namespaces "${tf_files[@]}"
