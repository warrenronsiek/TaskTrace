---
name: TaskTrace Knowledge Graph
description: This skill should be used when the user asks about what they know, what they have read, what they have learned, or what is in their notes, documents, or knowledge base. Trigger phrases include "what do I know about X", "find notes on X", "what have I read about X", "what's in my knowledge base", "find claims about X", "what communities relate to X", "what does the graph know", "summarize what I know", and any question where the answer lives in the user's curated knowledge rather than in their activity history. Powered by TaskTrace's graph RAG over the user's currently selected knowledge directory.
---

# TaskTrace Knowledge Graph

TaskTrace builds a knowledge graph — communities, nodes, edges, and claims — over a directory of the user's content that they selected inside TaskTrace. The graph mixes everything TaskTrace has ingested for that directory: notes the user wrote, documents they read, and anything extracted from screen captures and transcripts that got promoted into persistent knowledge. Treat the graph as a single source: it answers "what does the user know or believe", not "what did the user do".

The `tasktrace_graph_search` tool queries this graph. It is separate from `tasktrace_search`, which ranks activity history.

## When to use this vs. activity search

Use `tasktrace_graph_search` when the question is about **knowledge**:
- "what do I know about OAuth refresh flows"
- "find claims about billing retries"
- "what communities relate to PDF parsing"
- "what does the graph say about X"
- "summarize what I've read on X"
- "is there anything in my notes about X"

Use `tasktrace_search` (see the `tasktrace-context` skill) when the question is about **activity**:
- "when did I last work on X"
- "what was I doing this morning"
- "find the session where I fixed X"

If the user's phrasing is ambiguous — "what do I have on X" — run both. The tools are cheap and cover different surfaces. Present the combined picture.

Do not try to distinguish for the user whether a piece of knowledge came from their notes, a PDF they read, or text extracted from a screenshot. The graph treats these uniformly on purpose. Answer from the graph content without apologizing for the provenance.

## Tool details

`tasktrace_graph_search` input:

```json
{
  "query": "string (required)",
  "limit": "number (optional, default 3, clamped to [1, 10])"
}
```

- `query` is natural language. Pass the user's phrasing through, cleaned of filler.
- `limit` is the number of reranked graph hits to keep. Default 3 is narrow by design; raise to 5–10 for exploratory questions ("everything I know about X").
- The tool runs hybrid vector + FTS retrieval, reranks matches, keeps the strongest, and returns the surrounding communities, nodes, edges, and claims with relevance metadata.
- Output is a `GraphRAGRetrievalResult`. Surface the content directly; the structure contains enough context (community summaries, node text, claim statements) that summarization can work from it without external lookup.

## Query strategy

- **Be concrete**: "OAuth token refresh edge cases" outperforms "auth stuff".
- **Reformulate on weak results**: if the first query returns little, try again with different terms. Graph search is sensitive to vocabulary.
- **Call multiple times for breadth**: several narrow queries beat one kitchen-sink query.
- **Pair with activity search for "am I working on this"**: the graph tells you what the user knows; activity search tells you whether it is in play right now.

## When the graph is empty

If `tasktrace_graph_search` returns no hits, the user may not have selected a knowledge directory in TaskTrace, or the selected directory has not been indexed. State that briefly — "the knowledge graph didn't return hits for that" — and offer to fall back to activity search if the question plausibly could be answered from recent work.

## Failure modes

- **Tool disabled** (user toggled it off): fall back to `tasktrace_search` over activity.
- **Graph RAG service unavailable**: the TaskTrace app may be in a mid-migration state. Suggest the user run `/tasktrace-mcp:setup` if this persists.
- **Empty `query`**: the tool rejects it. Validate input before calling.
