#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/.." && pwd)"
BIG_TEXT_DIR="$REPO_ROOT/AppResources/LocalModels/Qwen3.5-4B-OptiQ-4bit"
SMALL_TEXT_DIR="$REPO_ROOT/AppResources/LocalModels/Qwen3.5-0.8B-OptiQ-4bit"
VISUAL_DIR="$REPO_ROOT/AppResources/LocalModels/gemma-4-e2b-it-4bit"
OLD_TEXT_DIRS=(
  "$REPO_ROOT/AppResources/LocalModels/Qwen3-8B-4bit"
)
OLD_VISUAL_DIRS=(
  "$REPO_ROOT/AppResources/LocalModels/gemma-3-4b-it-qat-4bit"
  "$REPO_ROOT/AppResources/LocalModels/gemma-4-e4b-it-4bit"
)

git lfs version >/dev/null 2>&1 || {
  echo "git-lfs is required to hydrate bundled models" >&2
  exit 1
}

if [ ! -f "$BIG_TEXT_DIR/model.safetensors" ] || [ ! -f "$BIG_TEXT_DIR/tokenizer.json" ] ||
  [ ! -f "$SMALL_TEXT_DIR/model.safetensors" ] || [ ! -f "$SMALL_TEXT_DIR/tokenizer.json" ]; then
  "$ROOT_DIR/scripts/vendor_text_model.sh"
else
  echo "Text models already present at $BIG_TEXT_DIR and $SMALL_TEXT_DIR"
fi

for OLD_TEXT_DIR in "${OLD_TEXT_DIRS[@]}"; do
  if [ -d "$OLD_TEXT_DIR" ]; then
    rm -rf "$OLD_TEXT_DIR"
  fi
done

for OLD_VISUAL_DIR in "${OLD_VISUAL_DIRS[@]}"; do
  if [ -d "$OLD_VISUAL_DIR" ]; then
    rm -rf "$OLD_VISUAL_DIR"
  fi
done

if [ ! -d "$VISUAL_DIR" ] ||
  [ ! -f "$VISUAL_DIR/config.json" ] ||
  ! find "$VISUAL_DIR" -maxdepth 1 -name '*.safetensors' -type f | grep -q . ||
  [ ! -f "$VISUAL_DIR/processor_config.json" ] ||
  [ ! -f "$VISUAL_DIR/tokenizer.json" ] ||
  [ ! -f "$VISUAL_DIR/tokenizer_config.json" ]; then
  "$ROOT_DIR/scripts/vendor_visual_model.sh"
else
  echo "Visual model already present at $VISUAL_DIR"
fi
