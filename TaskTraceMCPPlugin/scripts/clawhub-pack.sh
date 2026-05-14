#!/usr/bin/env bash
# Creates a flat zip for release/upload of the full OpenClaw package layout.
# The archive root contains the shared MCP bundle metadata plus the native
# OpenClaw resource-backed tool bridge.
set -euo pipefail

VERSION="${1:?Usage: clawhub-pack.sh <version>}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
ZIPFILE="$DIST_DIR/tasktrace-mcp-${VERSION}.zip"

mkdir -p "$DIST_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.codex-plugin" "$TMP/.claude-plugin" "$TMP/.cursor-plugin" "$TMP/assets" "$TMP/src"

cp "$REPO_ROOT/package.json"                "$TMP/"
cp "$REPO_ROOT/index.js"                    "$TMP/"
cp "$REPO_ROOT/openclaw.plugin.json"        "$TMP/"
cp "$REPO_ROOT/README.md"                   "$TMP/"
cp "$REPO_ROOT/.mcp.json"                   "$TMP/"
cp "$REPO_ROOT/.codex-plugin/plugin.json"   "$TMP/.codex-plugin/"
cp "$REPO_ROOT/.claude-plugin/plugin.json"  "$TMP/.claude-plugin/"
cp "$REPO_ROOT/.cursor-plugin/plugin.json"  "$TMP/.cursor-plugin/"
cp "$REPO_ROOT/assets/favicon-192x192.png"  "$TMP/assets/"
cp "$REPO_ROOT/assets/tasktrace-logo-black-bg.svg" "$TMP/assets/"
cp "$REPO_ROOT/src/tasktrace-mcp-client.js" "$TMP/src/"
cp "$REPO_ROOT/src/tasktrace-tools.js"      "$TMP/src/"

cd "$TMP"
zip -r "$ZIPFILE" .
echo "Created $ZIPFILE"
