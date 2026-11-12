#!/usr/bin/env bash
# Checks the files in this folder against the SHA-256 fingerprints in ../v2-preregistration.md,
# written before any v2 run. Tasks and the planted patch must be here and unchanged. The runner
# and the judge are kept outside the repo; their fingerprints are listed but not checked here.
# Exits 1 if a file here differs from its fingerprint, or a task or patch is missing.
set -uo pipefail
cd "$(dirname "$0")"
fail=0 checked=0 outside=0
while IFS= read -r line; do
  file="$(echo "$line" | cut -d'`' -f2)"
  want="$(echo "$line" | cut -d'`' -f4)"
  if [ -f "$file" ]; then
    checked=$((checked + 1))
    if [ "$(sha256sum "$file" | cut -d' ' -f1)" = "$want" ]; then echo "ok       $file"; else echo "CHANGED  $file"; fail=1; fi
  elif [[ "$file" == tasks/* || "$file" == patches/* ]]; then
    echo "MISSING  $file"; fail=1
  else
    outside=$((outside + 1))
    echo "outside  $file (kept outside the repo)"
  fi
done < <(grep '^| `' ../v2-preregistration.md)
echo "$checked files checked against the pre-registration; $outside kept outside the repo"
exit "$fail"
