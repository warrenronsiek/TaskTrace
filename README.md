# TaskTrace

TaskTrace is an open-source macOS app for recording work activity and turning it
into searchable local context. It captures screenshots, keystrokes, and
microphone activity after the user starts recording, stores that data locally,
and uses bundled local AI models to build summaries, tags, overviews, knowledge
graphs, and agent-readable context.

## What Is In This Repo

- `TaskTrace/`: SwiftUI macOS app.
- `TaskTraceTests/`: unit and integration tests for the app.
- `TaskTraceUITests/`: UI test target.
- `TaskTraceWeb/`: public website and download surface. See `TaskTraceWeb/README.md`.
- `TaskTraceWebView/`: JavaScript renderers embedded by the app.
- `TaskTraceMCPPlugin/`: Claude Code, Codex, and OpenClaw plugin bundle for TaskTrace MCP.
- `BrowserPlugin/`: browser capture extension and native messaging support.
- `Infra/`: Terraform for public web and release artifact hosting. See `Infra/README.md`.
- `.circleci/`: CI, release, signing, notarization, and deploy workflow. See `.circleci/README.md`.
- `MLXConversion/`: local-model conversion and packaging tools.
- `AppResources/`: bundled models and app resources.
- `Vendor/`: vendored dependencies used by the app build.

Legacy reference material is intentionally kept out of the root overview. Check
module READMEs and architecture notes near the code you are changing.

## App Features

- Local screenshot, keystroke, and microphone capture for work sessions.
- Local AI summaries for activities and screenshots.
- Calendar, overview, tags, analytics, and stats views.
- Full-text and AI-assisted search over captured work context.
- Knowledge graph generation from activity and selected local knowledge folders.
- MCP resources for connecting TaskTrace context to external AI tools.
- Browser-plugin capture for web-page context.

## Architecture Map

The app follows a SwiftUI store plus actor model: UI stores expose observable
state on the main actor, while actors handle persistence, AI work, and domain
logic. SQLite is the source of truth for durable app state.

Start with these docs when working in a specific subsystem:

- `TaskTrace/Activity/ACTIVITY_ARCHITECTURE.md`
- `TaskTrace/AI/AI_ARCHITECTURE.md`
- `TaskTrace/DB/DB_ARCHITECTURE.md`
- `TaskTrace/Overview/OVERVIEW_ARCHITECTURE.md`
- `TaskTrace/Search/README.md`
- `TaskTrace/MCP/README.md`
- `TaskTraceWeb/README.md`
- `.circleci/README.md`

High-value app entry points:

- `TaskTrace/App.swift`: runtime composition and subsystem bootstrapping.
- `TaskTrace/ContentView.swift`: root navigation shell.
- `TaskTrace/Vars.swift`: product constants and build-time integration values.
- `TaskTrace/DB/Database.swift`: database wrapper and public persistence API.
- `TaskTrace/DB/DatabaseBootstrap.swift`: migrations and SQLite connection setup.

## Build The macOS App

Resolve packages:

```bash
xcodebuild -resolvePackageDependencies \
  -project TaskTrace.xcodeproj \
  -scheme TaskTrace
```

Build:

```bash
xcodebuild build \
  -project TaskTrace.xcodeproj \
  -scheme TaskTrace
```

Run tests:

```bash
xcodebuild test \
  -project TaskTrace.xcodeproj \
  -scheme TaskTrace
```

The app target generates its Info.plist from Xcode build settings.

## Build The Website

```bash
cd TaskTraceWeb
corepack enable
pnpm install --frozen-lockfile
pnpm dev
```

Production build:

```bash
pnpm build:prod
```

## Knowledge Graph Renderer Benchmark

If you change `TaskTraceWebView/src/renderers/knowledgeGraph.js`, use the
real-browser benchmark harness documented in `TaskTraceWebView/BENCHMARKS.md`.

```bash
cd TaskTraceWebView
npm run benchmark:knowledge-graph
```

## Release And Deployment

CircleCI builds the website, archives the macOS app, signs and notarizes the
DMG, generates the Sparkle appcast, and uploads release artifacts. Release
versioning is driven by semantic-release at the repo root:

- `package.json`
- `.releaserc.json`
- `versionUpdate.js`

Use `.circleci/README.md` for CI and signing details. Use
`OPEN_SOURCE_RELEASE.md` for the one-time public repository release runbook.

## License

TaskTrace is released under the MIT License. See `LICENSE`.
