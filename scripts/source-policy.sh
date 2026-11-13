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

echo "== Guard: test files use only mock providers and no external modules"
bad_tests="$(grep -rnE '^\s*(source\s*=|provider\s+")' --include='*.tftest.hcl' terraform || true)"
if [ -n "$bad_tests" ]; then
  echo "$bad_tests"
  echo "FAIL: .tftest.hcl files may not load modules (source =) or configure real providers (only mock_provider)."
  exit 1
fi
echo "ok"

echo "== Conftest: escape hatches in .tf files"
mapfile -t tf_files < <(find terraform -name '*.tf' -not -path '*/.terraform/*' | sort)
if [ "${#tf_files[@]}" -eq 0 ]; then
  echo "FAIL: no .tf files found, nothing was checked."
  exit 1
fi
conftest test --parser hcl2 --policy policies/hcl --namespace hcl.escape_hatches "${tf_files[@]}"

# Bootstrap is left out: its CI roles allow whole services on purpose
# (ADR 0002). It is a protected path, applied by hand by the owner.
echo "== Conftest: IAM least privilege in .tf files (envs and modules)"
mapfile -t workload_files < <(printf '%s\n' "${tf_files[@]}" | grep -v '^terraform/bootstrap/')
if [ "${#workload_files[@]}" -eq 0 ]; then
  echo "FAIL: no workload .tf files found, nothing was checked."
  exit 1
fi
conftest test --parser hcl2 --policy policies/hcl --namespace hcl.iam_source "${workload_files[@]}"
