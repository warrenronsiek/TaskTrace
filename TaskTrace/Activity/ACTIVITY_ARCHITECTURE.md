# Activity

This directory owns in-memory activity state and activity-domain messages.

## Current model

- `ActivityActor` is the in-memory projection of activity state.
- `ActivityStore` is the UI-facing observable wrapper.
- Source events are broadcast once and then projected independently by:
  - `ActivityActor`
  - DB actors
  - downstream overview / AI workers

## Expectations

- `ActivityActor` should update its own state and broadcast source events when it is the origin of a mutation.
- It should not call DB helpers directly.
- It should not call AI methods directly.
- It should not invent relay events after handling another event unless the new event is a true new source fact.

## Anti-patterns

- No `persist*` helper paths from `ActivityActor`.
- No `isApplying*` / "am I already processing?" loop guards to orchestrate AI work.
- No state snapshot rebroadcasts used to drive persistence.
