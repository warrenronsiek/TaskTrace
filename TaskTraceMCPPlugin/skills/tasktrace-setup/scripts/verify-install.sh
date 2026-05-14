#!/usr/bin/env bash
# Verify that TaskTrace.app is installed and reachable for MCP use.
# Safe to run at any time; no side effects.

set -u

APP_PATH="/Applications/TaskTrace.app"
BIN_PATH="${APP_PATH}/Contents/MacOS/TaskTrace"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"

printf "TaskTrace install check\n"
printf "=======================\n\n"

status=0

if [ -d "$APP_PATH" ]; then
  printf "[ok] TaskTrace.app found at %s\n" "$APP_PATH"
else
  printf "[missing] TaskTrace.app not found at %s\n" "$APP_PATH"
  printf "         Download from https://tasktrace.com and move it into /Applications.\n"
  status=1
fi

if [ -x "$BIN_PATH" ]; then
  printf "[ok] TaskTrace binary is executable\n"
else
  if [ -d "$APP_PATH" ]; then
    printf "[warn] TaskTrace binary is not executable at %s\n" "$BIN_PATH"
    status=1
  fi
fi

if [ -f "$PLIST_PATH" ]; then
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH" 2>/dev/null || true)"
  if [ -n "${version:-}" ]; then
    printf "[ok] TaskTrace version: %s\n" "$version"
  fi
fi

if pgrep -fq 'TaskTrace.app/Contents/MacOS/TaskTrace'; then
  printf "[ok] TaskTrace is currently running\n"
else
  printf "[info] TaskTrace is not running. Launch it from /Applications (Claude Code starts the MCP server on demand via --mcp-stdio, but the app must be installed).\n"
fi

printf "\nNext steps\n"
printf '%s\n' "----------"
printf "1. Open TaskTrace > Preferences > MCP and ensure 'Enable MCP server' is on.\n"
printf "2. In the same pane, enable the resources and tools you want Claude to see:\n"
printf "   - Active Day Overviews (today's grouped work)\n"
printf "   - High Level Activities (recent completed activity summaries)\n"
printf "   - Detailed Activities (keystrokes, transcripts, screenshots — off by default)\n"
printf "   - Activity Search tool\n"
printf "   - Graph Search tool\n"
printf "3. In Claude Code, run: /mcp   and confirm the 'tasktrace' server is listed.\n"
printf "4. Ask Claude something like 'what did I do today' to exercise the integration.\n"

if [ "$status" -ne 0 ]; then
  printf "\nOne or more checks failed. Install or repair TaskTrace before retrying.\n"
  exit 1
fi

printf "\nAll install checks passed.\n"
exit 0
