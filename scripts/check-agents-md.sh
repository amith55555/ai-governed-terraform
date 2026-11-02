#!/usr/bin/env bash

set -euo pipefail

FILE="AGENTS.md"
MAX_LINES=120
MAX_SKILL_LINES=150
missing=0

check_paths() {  # $1 = the file the paths came from; the paths arrive on stdin
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    if [ -e "$path" ]; then
      echo "ok       $path"
    else
      echo "MISSING  $path (in $1)"
      missing=1
    fi
  done
}

echo "== AGENTS.md: length"
lines=$(wc -l < "$FILE")
echo "$lines lines (max $MAX_LINES)"
if [ "$lines" -gt "$MAX_LINES" ]; then
  echo "FAIL: $FILE is too long. Move details into a skill."
  exit 1
fi

echo "== AGENTS.md: links point to real files"
links=$(grep -oE '\]\([^)#]+' "$FILE" | sed 's/^](//' | grep -vE '^https?://' | sort -u || true)
if [ -z "$links" ]; then
  echo "FAIL: no links found in $FILE."
  exit 1
fi
check_paths "$FILE" <<< "$links"

echo "== Skills: front matter, length, paths"
mapfile -t skills < <(find .claude/skills -name SKILL.md 2>/dev/null | sort)
if [ "${#skills[@]}" -eq 0 ]; then
  echo "FAIL: no skills found in .claude/skills/."
  exit 1
fi
for skill in "${skills[@]}"; do
  name=$(basename "$(dirname "$skill")")
  if [ "$(head -n 1 "$skill")" != "---" ] || ! grep -qx "name: $name" "$skill" || ! grep -qE '^description: .{40,}' "$skill"; then
    echo "FAIL: $skill needs front matter with 'name: $name' and a description of at least 40 characters."
    exit 1
  fi
  skill_lines=$(wc -l < "$skill")
  echo "$skill: $skill_lines lines (max $MAX_SKILL_LINES)"
  if [ "$skill_lines" -gt "$MAX_SKILL_LINES" ]; then
    echo "FAIL: $skill is too long."
    exit 1
  fi
  check_paths "$skill" < <(grep -oE '`(terraform|policies|docs|risk|scripts|app|\.github|\.claude)/[^`<* ]+`' "$skill" | tr -d '`' | sort -u)
done

if [ "$missing" -ne 0 ]; then
  echo "FAIL: some instructions point to files that do not exist."
  exit 1
fi
