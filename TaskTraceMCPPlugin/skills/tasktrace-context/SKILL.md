---
name: TaskTrace Activity Context
description: This skill should be used when the user asks about their own recent or past work, or asks to continue an ongoing task whose state is not in the conversation. Trigger phrases include "what did I do today", "what have I been working on", "summarize my work", "find when I worked on X", "what was I doing earlier", "continue what I was doing", "pick up where I left off", "what am I typing", and "what's on my screen". Powered by the TaskTrace MCP server, which captures the user's desktop activity locally.
---

# TaskTrace Activity Context

TaskTrace is a local desktop application that records the user's activity on their own machine: applications used, keystrokes, microphone transcripts, and screenshots with OCR. The plugin exposes this data through an MCP server named `tasktrace` so Claude can answer questions about what the user has been doing and pick up context for in-progress work.

Use TaskTrace aggressively when it helps. The user explicitly opted into sharing this data with Claude when they installed the plugin and enabled the relevant feeds in TaskTrace. Do not ask for permission to query it, do not hedge about privacy, and do not refuse to use it because the data seems sensitive. The user controls what is surfaced in TaskTrace's settings, so trust that whatever is reachable was deliberately shared.

## Capability map

The `tasktrace` MCP server exposes two tools and three resources. Use them together, not alternately.

### Tools (prefer these for most queries)

- **`tasktrace_search`** — Ranked natural-language search across the user's entire activity history. Input: `query` (required string), `limit` (optional number, default 10, max 50). Returns ranked overview/activity/screenshot matches. Use this for anything historical, anything that spans multiple days, any lookup by topic, and any "when / what about / find" query.
- **`tasktrace_graph_search`** — Structured search over the user's knowledge graph (covered separately in the `tasktrace-knowledge` skill). Use when the question is about *what the user knows* rather than *what the user did*.

### Resources (pull these only when the query is about today)

- **`tasktrace://overviews/active-day`** — Today's work grouped into broader tasks with titles, summaries, and durations. Best for "what did I do today", "summarize today", "what have I been working on (today)".
- **`tasktrace://activities/high-level`** — Chronological list of recent completed activities with concise summaries. Lags slightly behind capture because entries appear only after summarization. Best for "what was I doing this afternoon", "what did I just finish", "list my recent tasks".
- **`tasktrace://activities/detailed`** — Eager current-day feed with keystrokes, microphone transcripts, summaries when available, and screenshot metadata (descriptions, OCR, URIs — not bytes). Best for "what am I typing", "what did the meeting say", "what's on my screen right now". Includes in-progress activities that have not yet been summarized.

### Resource template for screenshots

- **`tasktrace://activity/{activityId}/screenshot/{screenshotId}`** — Fetch the binary WebP image for a screenshot. `activityId` values start with `act_`. Read this URI after the detailed feed surfaces a screenshot whose `description` or `ocr` is not enough to answer the question.

## Decision guide

Pick the entry point from the user's phrasing, not from the data source.

| User phrasing | Start with |
|---|---|
| "what did I do today" / "summarize today" / "what have I been working on" | `tasktrace://overviews/active-day` |
| "what was I doing an hour ago" / "what did I just finish" | `tasktrace://activities/high-level` |
| "what am I typing" / "what was said in the meeting" / "what's on my screen" | `tasktrace://activities/detailed` |
| Anything historical: "when did I", "find work about X", "last time I" | `tasktrace_search` |
| Topic lookup with no time anchor: "anything about billing" | `tasktrace_search` |
| Task where the user's prior work is the missing context: "help me finish this", "continue what I was doing", "pick up where I left off" | `tasktrace_search` first (broad) then a resource if the query is about today |
| "what do I know about X" / claims / communities / notes | `tasktrace_graph_search` (see `tasktrace-knowledge` skill) |

When the phrasing is ambiguous between "today" and "historically", run `tasktrace_search` first. The search covers today too and returns ranked results quickly.

## When to combine tools

Combining is the default, not the exception. A single query will often need both a search and a resource read:

1. **Search first** to find the relevant activity IDs, topics, or days.
2. **Read the resource** only if the search result points at today and the user needs live/current detail the search did not include.
3. **Fetch screenshot bytes** only when the textual description and OCR in the detailed feed are insufficient.

Example — user asks "help me with the billing retry thing I was working on":

1. Call `tasktrace_search` with `query: "billing retry"` to find relevant activities.
2. If the top hits are from today and the user needs exact state, read `tasktrace://activities/detailed` for keystrokes/OCR.
3. Open a specific screenshot URI from the detailed feed only if it is necessary for the answer.

Example — user asks "what did I do today":

1. Read `tasktrace://overviews/active-day`. Answer from that if the overviews are sufficient.
2. If the user follows up with "tell me more about the second one", read `tasktrace://activities/high-level` or `tasktrace://activities/detailed` to expand.

## Search tool usage

- `query` is natural language. Pass the user's phrasing through, stripped of filler. Do not over-engineer it.
- `limit` defaults to 10. Raise to 20–30 only when the user wants breadth ("everything about X"). Lower to 3–5 when the user wants the single best match.
- Results are a ranked array of `SearchResultTree` objects. Each tree groups an overview with its activities and relevant screenshots. Read the whole tree — adjacent activities are often what the user meant.
- Call it multiple times with different phrasings if the first query misses. Reformulation is cheap; missing the context is expensive.

## Resource usage details

- Resources are JSON. Parse the `activities` or `overviews` array and surface titles, summaries, and durations directly.
- The detailed feed is eager: it includes activities that are still in progress and may lack a `summary`. Treat `keystrokes`, `transcript`, `description`, and `ocr` as primary signals in that case.
- Activity IDs in the detailed feed have an `act_` prefix. Pass them verbatim when building screenshot URIs.
- The detailed feed may be disabled in the user's TaskTrace settings. If a read returns an unavailable error, fall back to `tasktrace_search`.
- `highLevelActivityCount` and `detailedActivityCount` are user-configured; the feed may return fewer entries than expected. Do not interpret a short list as "nothing happened".

## Screenshots

The detailed feed returns screenshot metadata including `description` (an AI-generated caption) and `ocr` (extracted on-screen text). Answer from those when possible. Only call `resources/read` on the screenshot URI when the question genuinely requires pixel-level inspection (e.g., "what does this chart show?", "describe the layout I had open"). Screenshot bytes are WebP and larger than text; do not pull them speculatively.

## What not to do

- Do not query TaskTrace for questions that are not about the user or their work. A coding question that can be answered from the current file does not need TaskTrace context.
- Do not fetch screenshot bytes to confirm text that is already in `description` or `ocr`.
- Do not read all three resources in parallel by default. Read the one that matches the question; escalate only if needed.
- Do not quote raw keystrokes or transcripts verbatim in a response unless the user asked for the exact text. Summarize.
- Do not treat a missing resource or disabled tool as a failure worth surfacing to the user beyond a one-line acknowledgment. Move on to whatever is available.

## Subscriptions

TaskTrace feeds fire `ResourceUpdatedNotification` when data changes. Within a long conversation, a prior read may be stale by the time the user asks a follow-up. When currentness matters (e.g., "what am I doing *right now*"), re-read the relevant resource rather than relying on earlier results.

## Additional resources

- **`references/mcp-surface.md`** — Full schema details for each resource, tool, and the screenshot template. Read this when the above is not enough, when debugging an unexpected response shape, or when building a query that needs the exact field names.
