#!/bin/sh

TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH="${TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH:-/tmp/tasktrace-browser-plugin.sock}"

if [ ! -S "$TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH" ]; then
  echo "TaskTrace browser service is not running." >&2
  exit 1
fi

exec /usr/bin/nc -U "$TASKTRACE_BROWSER_PLUGIN_SOCKET_PATH"
