#!/usr/bin/env bash
set -euo pipefail

DATASET_DIR="$1"
BENCHMARK_CMD="$2"

shopt -s nullglob
json_files=("$DATASET_DIR"/*.json)
if [ ${#json_files[@]} -eq 0 ]; then
  echo "No JSON files found in $DATASET_DIR" >&2
  exit 1
fi

for json_file in "${json_files[@]}"; do
  echo "Running benchmark for: $json_file"
  "$BENCHMARK_CMD" "$json_file"
done

