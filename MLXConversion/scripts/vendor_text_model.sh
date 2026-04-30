#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
OLD_TEXT_DIRS=(
  "$REPO_ROOT/AppResources/LocalModels/Qwen3-8B-4bit"
)

git lfs version >/dev/null 2>&1 || {
  echo "git-lfs is required to vendor text models" >&2
  exit 1
}

git lfs install --skip-repo

vendor_model() {
  local source_repo="$1"
  local output_dir="$2"
  local temp_dir="$3"

  mkdir -p "$(dirname "$output_dir")"
  mkdir -p "$(dirname "$temp_dir")"
  rm -rf "$temp_dir"

  local command=(
    git
    clone
    "https://huggingface.co/$source_repo"
    "$temp_dir"
  )

  printf 'Running: %q ' "${command[@]}"
  printf '\n'
  "${command[@]}"
  (
    cd "$temp_dir"
    git lfs install --local
    git lfs pull
  )

  rsync -a --delete --exclude '.git' "$temp_dir"/ "$output_dir"/
  rm -rf "$temp_dir"

  echo "Vendored $source_repo into $output_dir"
}

if [ -n "${SOURCE_REPO:-}" ] || [ -n "${OUTPUT_DIR:-}" ] || [ -n "${TEMP_DIR:-}" ]; then
  vendor_model \
    "${SOURCE_REPO:-mlx-community/Qwen3.5-4B-OptiQ-4bit}" \
    "${OUTPUT_DIR:-$REPO_ROOT/AppResources/LocalModels/Qwen3.5-4B-OptiQ-4bit}" \
    "${TEMP_DIR:-$ROOT_DIR/tmp/Qwen3.5-4B-OptiQ-4bit}"
else
  vendor_model \
    "mlx-community/Qwen3.5-4B-OptiQ-4bit" \
    "$REPO_ROOT/AppResources/LocalModels/Qwen3.5-4B-OptiQ-4bit" \
    "$ROOT_DIR/tmp/Qwen3.5-4B-OptiQ-4bit"
  vendor_model \
    "mlx-community/Qwen3.5-0.8B-OptiQ-4bit" \
    "$REPO_ROOT/AppResources/LocalModels/Qwen3.5-0.8B-OptiQ-4bit" \
    "$ROOT_DIR/tmp/Qwen3.5-0.8B-OptiQ-4bit"
fi

for OLD_TEXT_DIR in "${OLD_TEXT_DIRS[@]}"; do
  if [ -d "$OLD_TEXT_DIR" ]; then
    rm -rf "$OLD_TEXT_DIR"
  fi
done
