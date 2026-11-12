#!/usr/bin/env bash
# Checks that the files in this folder are exactly the ones fingerprinted in
# ../v2-preregistration.md before any v2 run. Exits 1 if any file differs or is missing.
set -uo pipefail
cd "$(dirname "$0")"
fail=0 count=0
while IFS= read -r line; do
  file="$(echo "$line" | cut -d'`' -f2)"
  want="$(echo "$line" | cut -d'`' -f4)"
  have="$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)"
  count=$((count + 1))
  if [ "$have" = "$want" ]; then echo "ok       $file"; else echo "CHANGED  $file"; fail=1; fi
done < <(grep '^| `' ../v2-preregistration.md)
echo "$count files checked against the pre-registration"
exit "$fail"