# DB

This directory contains database actors and persistence primitives.

## Current model

- DB actors subscribe directly to source events from the actor system.
- They persist those facts to SQLite.
- They do not own UI state.

## Expectations

- A DB actor should listen to the original domain event whenever possible.
- If `ActivityActor` and a DB actor both care about an event, both should subscribe to the same source event.
- DB actors should not depend on follow-on relay events created only for persistence.

## Anti-patterns

- No `TaskTraceDomainEvents` side channel.
- No persistence triggers emitted after another actor already handled the same event.
- No coupling between "UI updated" and "DB saved".

## Rule of thumb

If a source event already contains enough information to persist the mutation, persist from that event directly.
