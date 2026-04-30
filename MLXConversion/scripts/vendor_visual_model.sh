#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-mlx-community/gemma-4-e2b-it-4bit}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/AppResources/LocalModels/gemma-4-e2b-it-4bit}"
OLD_OUTPUT_DIRS=(
  "$REPO_ROOT/AppResources/LocalModels/gemma-3-4b-it-qat-4bit"
  "$REPO_ROOT/AppResources/LocalModels/gemma-4-e4b-it-4bit"
)
TEMP_DIR="${TEMP_DIR:-$ROOT_DIR/tmp/gemma-4-e2b-it-4bit}"

git lfs version >/dev/null 2>&1 || {
  echo "git-lfs is required to vendor $SOURCE_REPO" >&2
  exit 1
}

git lfs install --skip-repo

mkdir -p "$(dirname "$OUTPUT_DIR")"
mkdir -p "$(dirname "$TEMP_DIR")"
rm -rf "$TEMP_DIR"

for OLD_OUTPUT_DIR in "${OLD_OUTPUT_DIRS[@]}"; do
  if [ -d "$OLD_OUTPUT_DIR" ] && [ "$OLD_OUTPUT_DIR" != "$OUTPUT_DIR" ]; then
    rm -rf "$OLD_OUTPUT_DIR"
  fi
done

command=(
  git
  clone
  "https://huggingface.co/$SOURCE_REPO"
  "$TEMP_DIR"
)

printf 'Running: %q ' "${command[@]}"
printf '\n'
"${command[@]}"
(
  cd "$TEMP_DIR"
  git lfs install --local
  git lfs pull
)

rsync -a --delete --exclude '.git' "$TEMP_DIR"/ "$OUTPUT_DIR"/
rm -rf "$TEMP_DIR"

echo "Vendored $SOURCE_REPO into $OUTPUT_DIR"
