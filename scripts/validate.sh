#!/usr/bin/env bash

set -euo pipefail

export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$HOME/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

for dir in terraform/bootstrap terraform/envs/dev terraform/envs/prod; do
  echo "== validate $dir"
  data_dir="$(mktemp -d)"
  TF_DATA_DIR="$data_dir" terraform -chdir="$dir" init -backend=false -input=false > /dev/null
  TF_DATA_DIR="$data_dir" terraform -chdir="$dir" validate
  rm -rf "$data_dir"
done
