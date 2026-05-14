---
name: TaskTrace Setup
description: This skill should be used when the user asks to "set up tasktrace", "install tasktrace", "configure tasktrace", "tasktrace isn't working", "check tasktrace", "verify tasktrace", "why can't claude see tasktrace", or any troubleshooting of the TaskTrace MCP connection. Runs local install checks, confirms TaskTrace.app is installed and running, and walks the user through enabling the MCP server, permissions, and plugin install. Also triggered by `/tasktrace-mcp:setup`.
---

# TaskTrace Setup

Help the user get TaskTrace wired up so Claude can see their activity and knowledge. This is a diagnosis-first skill: run checks, then give the user only the steps they actually need.

## Workflow

Run all four phases in order. Skip later phases if an earlier one fails — fix upstream first.

### Phase 1: Run local checks

Execute the verification script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/tasktrace-setup/scripts/verify-install.sh
```

The script reports:
- Whether `/Applications/TaskTrace.app` exists
- Whether the binary is executable
- The installed TaskTrace version
- Whether TaskTrace is currently running

Read the script output carefully. If any line is `[missing]` or `[warn]`, prioritize the fix in Phase 2 before moving on.

### Phase 2: Guide install and app-level setup

Based on the script output, walk the user through only the missing pieces.

#### If TaskTrace.app is not installed

1. Download from https://tasktrace.com and move the app to `/Applications`.
2. Launch it once to complete macOS Gatekeeper checks.
3. Re-run the verification script.

#### If TaskTrace.app is installed but not running

Ask the user to launch TaskTrace from `/Applications`. The MCP server is started on demand by Claude Code via `--mcp-stdio`, but the app must be installed and permitted to access input, screen, and microphone if they want those feeds populated.

#### Enable the MCP server inside TaskTrace

Direct the user to:

1. Open TaskTrace.
2. Go to **Preferences → MCP**.
3. Toggle **Enable MCP server** on.
4. Toggle individual resources and tools as desired:
   - **Active Day Overviews** — today's work grouped into broader tasks. Low-sensitivity. Usually on.
   - **High Level Activities** — recent completed activity summaries. Low-sensitivity. Usually on.
   - **Detailed Activities** — keystrokes, transcripts, screenshot metadata. Off by default; opt in if the user wants Claude to read in-progress work.
   - **Activity Search** — natural-language search across history. Recommended on.
   - **Graph Search** — structured retrieval over the user's knowledge directory. Recommended on.

Make explicit that each toggle controls what Claude sees. Whatever the user enables is what Claude will use — no additional permission prompts.

### Phase 3: Verify the plugin is installed in Claude Code

Ask the user to run the following inside Claude Code:

```text
/mcp
```

They should see a server listed as `tasktrace` or `plugin:tasktrace-mcp-plugin:tasktrace`. If it is not listed, the plugin itself is missing or disabled.

#### Install the plugin (if missing)

Preferred: install via the marketplace.

```bash
git clone https://github.com/warrenronsiek/TaskTrace.git
cd TaskTrace/TaskTraceMCPPlugin
```

Then run inside Claude Code:

```text
/plugin marketplace add .
/plugin install tasktrace-mcp@tasktrace-mcp
/reload-plugins
```

Alternative: register the MCP server directly (no plugin skills, just the tools and resources).

```bash
claude mcp add --transport stdio --scope user tasktrace -- /Applications/TaskTrace.app/Contents/MacOS/TaskTrace --mcp-stdio
```

After either install path, run `/mcp` again.

### Phase 4: Smoke test

Ask the user to run a question that exercises the integration, for example:

> what did I do today

Expect Claude to read `tasktrace://overviews/active-day` and answer from it. If Claude answers without calling TaskTrace, something is still wrong — go back to Phase 3.

## Common failures and fixes

| Symptom | Cause | Fix |
|---|---|---|
| Script reports `[missing]` for TaskTrace.app | Not installed | Install from https://tasktrace.com |
| `/mcp` does not list `tasktrace` | Plugin not installed, or Claude Code session started before install | Install the plugin; restart the session |
| `tasktrace` listed but tool calls fail with "disabled" | User turned off that tool in TaskTrace Preferences → MCP | Toggle the tool on |
| Resource reads return empty `activities` | User has not worked today, or capture is paused | No fix needed; state plainly |
| App runs but screenshots are empty | Screen Recording permission not granted in macOS System Settings | Grant permission in System Settings → Privacy & Security → Screen & System Audio Recording |
| Keystrokes missing from detailed feed | Input Monitoring permission not granted | Grant in System Settings → Privacy & Security → Input Monitoring |
| Transcripts missing | Microphone permission not granted, or dictation not active | Grant microphone access and toggle transcription in TaskTrace |

## Output style

Keep responses terse. After running the script, report only:
- One sentence of status ("TaskTrace is installed and running, MCP server enabled").
- The specific next step if anything is missing.
- The smoke-test prompt if everything is ready.

Do not restate everything the script printed — the user already saw it.
