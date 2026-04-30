# Overview

This directory owns overview state, overview-domain messages, and overview UI/store code.

## Current model

- `OverviewActor` is the in-memory projection of overview state.
- Ontology-driven overview refresh and merge AI work is performed by worker actors in `AI/`.
- Persistence is handled by DB actors in `DB/`.
- Overview state should react directly to source events like:
  - `OverviewMergeResolved`
  - `OverviewDayReloadRequested`

## Expectations

- `OverviewActor` updates local overview state only.
- It may emit source requests such as merge computation requests.
- It should not translate one handled event into a chain of synthetic relay events just to keep other actors in sync.
- If another actor needs to respond to an overview event, that actor should subscribe to that event directly.

## Anti-patterns

- No `upsertOverview` style "update state, then relay a second event" helpers.
- No `OverviewUpserted` / `OverviewsMerged` style pseudo-events for internal plumbing.
- No coupling of UI state changes to DB writes.
