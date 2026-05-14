#!/usr/bin/env zsh

openclaw plugins uninstall tasktrace-mcp
rm -rf ~/.openclaw/extensions/tasktrace-mcp
openclaw plugins install .
