# AI

This directory now owns AI work as lane-based worker actors.

## Current model

- There is no monolithic `ActivityAI.swift` anymore.
- Each AI lane has:
  - a session manager / concurrency gate
  - one or more actors that receive requests from the actor system
- Prompt strings and parsing logic live on the relevant actor, not in a shared god object.

## Expectations

- One actor per lane or per coherent worker role.
- Session managers own model loading, concurrency, and permit logic.
- Worker actors own prompting, model invocation, parsing, and result-event broadcast.
- Do not reintroduce direct `ActivityActor -> AI service method -> ActivityActor` loops.
- Do not add "processing loop" booleans in other actors to compensate for AI orchestration. Queueing belongs inside the AI worker actor.

## Anti-patterns

- Do not rebuild `ActivityAI`.
- Do not make AI actors into thin shims around some other central service.
- Do not hide prompt/parsing logic in unrelated files.
