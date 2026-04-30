# MCP

This module exposes TaskTrace context to local MCP clients.

## What It Serves

The MCP server publishes local TaskTrace data from SQLite. It does not own
activity, overview, or settings state.

Main resources:

- `tasktrace://overviews/active-day`: active-day overview titles, summaries, and durations.
- `tasktrace://activities/high-level`: recent completed activities with summary-level data.
- `tasktrace://activities/detailed`: eager recent activity data, including incomplete activities and screenshot metadata.
- `tasktrace://activity/{activityId}/screenshot/{screenshotId}`: screenshot image bytes fetched through a resource template.

Screenshot bytes are intentionally fetched separately rather than embedded in
the detailed activity feed.

## Main Files

- `OverviewMCPServer.swift`: stdio MCP runtime and resource handlers.
- `TaskTraceMCPStdioProxy.swift`: app-side stdio proxy support.
- `TaskTraceMCPHelperLauncher.swift`: helper executable discovery and launch.
- `MCPView.swift`: in-app MCP setup instructions.
- `TaskTrace/MCP/TaskTraceDomainEvents.swift`: distributed notifications that wake MCP clients after local data changes.

## Refresh Model

MCP refresh is event-driven:

- activity persistence posts activity change notifications
- overview persistence posts overview change notifications
- MCP settings writes post configuration change notifications
- the stdio process reloads the relevant data from SQLite and emits MCP update notifications

Keep this path database-backed. Do not add long-lived in-memory copies of large
activity, screenshot, or knowledge payloads to the MCP process.

## External Plugin Repo

The app points users to `warrenronsiek/TaskTraceMCPPlugin` for OpenClaw,
Claude, Cursor-compatible bundle metadata, and release packaging.
