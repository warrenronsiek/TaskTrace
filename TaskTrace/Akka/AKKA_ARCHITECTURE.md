# Akka

This directory contains the minimal actor runtime used by the rest of the app.

## Current model

- `ActorSystem` is the message bus.
- Messages are plain `Sendable` structs.
- Receivers subscribe by being registered with the system.
- We currently favor broad `broadcast` over selective routing.

## Expectations

- Keep this layer small.
- Do not push business logic into the actor system.
- The actor system should deliver messages, not reinterpret them.
- Subsequent optimization should happen by improving routing, not by adding domain-specific branching here.

## Likely future work

- Add explicit subscription metadata so we stop broadcasting every event to every actor.
- Route by event id before delivery so receivers do less `case let event as ...` matching.
