#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-Qwen/Qwen3-Reranker-0.6B}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/models/Qwen3-Reranker-0.6B-4bit}"
Q_BITS="${Q_BITS:-4}"
Q_MODE="${Q_MODE:-affine}"

if [[ -d "$ROOT_DIR/.venv" ]]; then
  VENV_DIR="$ROOT_DIR/.venv"
elif [[ -d "$ROOT_DIR/venv" ]]; then
  VENV_DIR="$ROOT_DIR/venv"
else
  echo "No virtualenv found. Expected $ROOT_DIR/.venv or $ROOT_DIR/venv." >&2
  exit 1
fi

command=(
  "$VENV_DIR/bin/python"
  -m
  mlx_embeddings.convert
  --hf-path "$SOURCE_REPO"
  --mlx-path "$OUTPUT_DIR"
  -q
  --q-bits "$Q_BITS"
  --q-mode "$Q_MODE"
)

if [[ -n "${Q_GROUP_SIZE:-}" ]]; then
  command+=(--q-group-size "$Q_GROUP_SIZE")
fi

if [[ -n "${UPLOAD_REPO:-}" ]]; then
  command+=(--upload-repo "$UPLOAD_REPO")
fi

printf 'Running: %q ' "${command[@]}"
printf '\n'
"${command[@]}"
