# Tasktrace

TaskTrace is a desktop application that records users keystrokes and screenshots and feeds that through LLMs. The goal is to create billables and allow for personal optimization.

All of tasktrace's marketing and concept is built around this - users know what they are doing when they install and press play. Its very explicit that we will
be taking screenshots and recording them. Thats the whole point.

This product has already been built once using ReactNative. We need to translate it into a pure swift/xcode project. We will proceed step by step.


## Style Guide

### Avoid tons of small functions
The only cases where you want to create "helper" functions is:
1. To stay DRY. You have the same functionality somewhere else and you are repeating it
2. To unit test. You have some complicated logic that needs to be independently tested.

Functions should encapsulate as much functionality as possible with as small of a call signature as possible given the functionality.

A single function should fully execute a logically seperable unit of business logic. 

Whenever you want to create an independent helper, instead of creating new functions, create inline closures and return destructured values:

Bad:
```swift
func compute() -> (Int, Int) {
    let a = 3
    let b = 4
    return (a + b, a * b)
}

let (sum, product) = compute()
```
Good:
```swift
let (sum, product) = {
    let a = 3
    let b = 4
    return (a + b, a * b)
}()
```

### Classes and State
Classes should exist in order to provide currying and wrap sets of related functions. The idea of wrapping a local mutable state is bad and should be avoided whenever possible. 

If you want to have some encapsulated local mutable state, use an actor. 

### Knowledge store rules
The knowledge store is especially sensitive to memory growth. Do not keep in-memory caches of knowledge files, knowledge events, scanned file payloads, graph payloads, or any other corpus-scale knowledge state inside actors, stores, or views.

The database is the source of truth for knowledge data. Any visualization that needs knowledge data should load it lazily from the database through the knowledge store. Any business logic that needs to know about other existing files, links, chunks, or events should query the database directly instead of retaining that data in process memory.

If a change introduces a pattern where `KnowledgeGraphActor` or related code saves all files or events in memory, that change is wrong and should be redesigned.

### Knowledge graph benchmark
If you change `TaskTraceWebView/src/renderers/knowledgeGraph.js` or any code that affects knowledge graph rendering performance, run the real-browser benchmark harness in `TaskTraceWebView/BENCHMARKS.md`.

From `TaskTraceWebView/`:
```bash
npm run benchmark:knowledge-graph
```

Future LLMs should use that benchmark, not `jsdom`, to judge pan smoothness, dropped frames, and initial render cost.

### Atomic tests
Tests should only have a single assertion in them. Use setup/fixtures to provide the necessary logic for setting up. Dummy example:

For:
```swift
actor Device {

    enum Command {
        case read(Int)
        case record(Double)
    }

    private var temp: Double?

    func handle(_ command: Command) -> Double? {

        switch command {

        case .record(let value):
            temp = value
            return nil

        case .read:
            return temp
        }
    }
}
```

Then:
```swift
import Testing

struct DeviceTests {

    func withDevice(
        _ block: (Device) async -> Void
    ) async {
        let device = Device()
        await block(device)
    }

    func withRecordedDevice(
        recordedTemperature: Double = 23.0,
        _ block: (Device) async -> Void
    ) async {
        await withDevice { device in
            _ = await device.handle(.record(recordedTemperature))
            await block(device)
        }
    }

    @Test("reading temperature returns nil when nothing is recorded")
    func readReturnsNilWhenUnknown() async {
        await withDevice { device in
            let result = await device.handle(.read(42))
            #expect(result == nil)
        }
    }

    @Test("reading after recording returns the stored value")
    func readAfterRecordReturnsValue() async {
        await withRecordedDevice { device in
            let result = await device.handle(.read(42))
            #expect(result == 23.0)
        }
    }

    @Test("overwriting temperature works")
    func overwriteTemperature() async {
        await withRecordedDevice { device in
            _ = await device.handle(.record(55.0))
            let result = await device.handle(.read(3))
            #expect(result == 55.0)
        }
    }

    @Test("recording twice still leaves a readable value")
    func readAfterSecondRecordReturnsLatestValue() async {
        await withRecordedDevice { device in
            _ = await device.handle(.record(23.0))
            let result = await device.handle(.read(1))
            #expect(result == 23.0)
        }
    }
}
```

### Avoid defensive programming
Incorporate try/catch logic in situations where calls are made to external services and/or systems are known to be unreliable.
What is not necessary is to add error handlers to logic that internally defined and failure modes are understood. Thats extra
code with no upside.

### Functional programming whenever possible
Avoid for loops, prefer map/reduce. Vars should almost never be declared (unless you have an actor).
