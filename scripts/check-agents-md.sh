#!/usr/bin/env bash

set -euo pipefail

FILE="AGENTS.md"
MAX_LINES=120

echo "== AGENTS.md: length"
lines=$(wc -l < "$FILE")
echo "$lines lines (max $MAX_LINES)"
if [ "$lines" -gt "$MAX_LINES" ]; then
  echo "FAIL: $FILE is too long. Move details into a skill."
  exit 1
fi

echo "== AGENTS.md: links point to real files"
mapfile -t links < <(grep -oE '\]\([^)#]+' "$FILE" | sed 's/^](//' | grep -vE '^https?://' | sort -u)
if [ "${#links[@]}" -eq 0 ]; then
  echo "FAIL: no links found in $FILE."
  exit 1
fi

missing=0
for link in "${links[@]}"; do
  if [ -e "$link" ]; then
    echo "ok       $link"
  else
    echo "MISSING  $link"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "FAIL: $FILE links to files that do not exist."
  exit 1
fi
