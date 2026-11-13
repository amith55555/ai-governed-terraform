#!/usr/bin/env bash
# Checks the tasks and the planted patch in this folder against the SHA-256 fingerprints in
# ../v2-preregistration.md, written before any v2 run. Exits 1 if one differs or is missing.
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
  fi
done < <(grep '^| `' ../v2-preregistration.md)
echo "$checked files checked against the pre-registration; $outside kept outside this repo (not checked)"
exit "$fail"
