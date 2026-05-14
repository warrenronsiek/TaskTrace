# TaskTrace MCP Surface Reference

Detailed schemas for the `tasktrace` MCP server. Refer to this when SKILL.md guidance is not specific enough, when parsing a response, or when an unexpected field appears.

Server identity:
- `name`: `tasktrace-mcp`
- `title`: `TaskTrace MCP Server`
- `version`: Drawn from the TaskTrace application's `CFBundleShortVersionString`
- Transport: `stdio`
- Capabilities: `resources.subscribe=true`, `resources.listChanged=true`, `tools.listChanged=true`

Every resource and tool is independently toggleable in TaskTrace's preferences. An `MCP disabled` or unavailable error means the user turned the feed or tool off. Fall back to another capability rather than surfacing that as an error.

## Resource: `tasktrace://overviews/active-day`

Name: *TaskTrace Active Day Overviews*. Default-enabled.

Returned JSON:

```json
{
  "date": "2026-04-18",
  "overviews": [
    {
      "id": "string",
      "title": "string",
      "summary": "string",
      "durationSeconds": 0
    }
  ]
}
```

- `date` is the ISO 8601 day the overviews belong to, from the user's local time zone.
- `overviews` groups the day's work into broader tasks/projects. The `summary` is a concise multi-sentence description; `durationSeconds` is total active time inside that overview.
- Subscribable: yes. Fires `ResourceUpdatedNotification` when overviews change.

## Resource: `tasktrace://activities/high-level`

Name: *TaskTrace High Level Activities*. Default-enabled. User-configurable entry count (1–11, default 5).

Returned JSON:

```json
{
  "date": "2026-04-18",
  "activities": [
    {
      "id": "string",
      "application": "string",
      "startTime": "2026-04-18T14:32:10Z",
      "durationSeconds": 0,
      "summary": "string",
      "tagID": "string",
      "overviewID": "string"
    }
  ]
}
```

- Only activities with a non-empty trimmed `summary` appear. In-progress or unsummarized work is excluded — that is what the detailed feed is for.
- Ordering is chronological (most recent last, or as delivered; do not depend on order for correctness — sort by `startTime` if it matters).
- Subscribable: yes.

## Resource: `tasktrace://activities/detailed`

Name: *TaskTrace Detailed Activities*. **Disabled by default** — the user opts in per feed. User-configurable entry count (1–11, default 5).

Returned JSON:

```json
{
  "date": "2026-04-18",
  "activities": [
    {
      "activityId": "act_12345",
      "application": "string",
      "startTime": "2026-04-18T14:32:10Z",
      "durationSeconds": 0,
      "keystrokes": "string",
      "transcript": "string",
      "summary": "string (optional)",
      "tagId": "string",
      "overviewId": "string",
      "screenshots": [
        {
          "screenshotId": 0,
          "uri": "tasktrace://activity/act_12345/screenshot/0",
          "mimeType": "image/webp",
          "timestamp": "2026-04-18T14:32:45Z",
          "width": 0,
          "height": 0,
          "size": 0,
          "description": "string",
          "ocr": "string",
          "ignoreReason": "string (optional)"
        }
      ]
    }
  ]
}
```

- `activityId` is prefixed with `act_`. Pass it verbatim into the screenshot URI template.
- `keystrokes` is the raw text the user typed during the activity. Microphone `transcript` is present only if dictation/transcription was active.
- `summary` is optional here; if absent, the activity is still in progress or not yet summarized.
- `screenshots[].description` is an AI-generated caption; `ocr` is extracted on-screen text. Prefer these over fetching the binary.
- `screenshots[].ignoreReason` is populated when TaskTrace intentionally skipped analyzing the frame (e.g., idle screen). Treat these as low-value.
- Subscribable: yes.

## Resource template: `tasktrace://activity/{activityId}/screenshot/{screenshotId}`

Name: *TaskTrace Activity Screenshot*. Enabled only when the detailed feed is enabled.

Parameters:
- `activityId`: string with the `act_` prefix. Example: `act_12345`.
- `screenshotId`: integer screenshot ID from the detailed feed.

Returns raw WebP image bytes. MIME: `image/webp`. Read via MCP `resources/read`.

Fetch only when the textual `description` and `ocr` in the detailed feed do not answer the question.

## Tool: `tasktrace_search`

Input schema:

```json
{
  "query": "string (required)",
  "limit": "number (optional, default 10, clamped to [1, 50])"
}
```

Output:

```json
{
  "query": "string (trimmed)",
  "limit": 10,
  "results": [
    {
      "rank": 1,
      "score": 0.0,
      "result": { /* SearchResultTree — overview with nested activities and screenshots */ }
    }
  ]
}
```

- `SearchResultTree` is hierarchical: an overview, its member activities, and any relevant screenshots. Surface adjacent entries together; they are usually what the user meant.
- An empty `query` after trimming returns an MCP error. Validate before calling.
- If `TaskTraceSearchService` is unavailable, the tool returns an MCP error; fall back to resource reads scoped to today.

## Tool: `tasktrace_graph_search`

See the `tasktrace-knowledge` skill. Input schema:

```json
{
  "query": "string (required)",
  "limit": "number (optional, default 3, clamped to [1, 10])"
}
```

Returns a `GraphRAGRetrievalResult` with communities, nodes, edges, claims, and relevance metadata. Operates on the knowledge directory currently selected in TaskTrace.

## Notifications

- `ResourceUpdatedNotification` — fired per subscribed URI when that resource's data changes.
- `ResourceListChangedNotification` — fired when the user toggles resources in settings.
- `ToolListChangedNotification` — fired when the user toggles tools in settings.

Re-read a resource when currentness matters (e.g., "what am I doing right now"). Do not assume a prior read within the same conversation is still fresh.

## Failure modes

| Symptom | Cause | Action |
|---|---|---|
| Resource read returns "not available" | User disabled that resource in TaskTrace preferences | Try another resource or a search |
| Tool call returns "disabled" | User disabled that tool | Fall back to resources |
| Empty `overviews` / `activities` array | User has not worked today, or capture paused | State that plainly; do not fabricate |
| Screenshot fetch returns empty | Screenshot was purged or the activity was deleted | Skip the visual and answer from text |
| MCP server not listed | TaskTrace.app not running, or `--mcp-stdio` not invoked | Direct the user to the `tasktrace-setup` skill |
