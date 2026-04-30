# TaskTrace Project Context

TaskTrace is a native macOS desktop application designed to capture user activity (screenshots, keystrokes, and microphone transcripts) and enrich it using local Machine Learning models (MLX Swift / MLXVLM). The goal is to automate task summarization, tagging, and billing optimization while keeping all data and processing local to the user's machine.

## Project Structure

- **`TaskTrace/`**: The main macOS application source code (Swift/Xcode).
  - **`Activity/`**: Logic for managing captured activity sessions.
  - **`AI/`**: Integration with MLX for on-device vision (Gemma 4) and summarization.
  - **`Settings/`**: Permissions and user configuration.
  - **`Database.swift`**: Persistence layer using SQLite and GRDB.
  - **`CaptureMonitor.swift`**: System-wide recording logic (screenshots, keys, audio).
- **`TaskTraceWeb/`**: React-based landing page and marketing site.
- **`Infra/`**: Terraform configurations for AWS (S3/CloudFront) hosting.
- **`.circleci/`**: CI/CD pipelines for macOS builds, signing, notarization, and deployment.

## Tech Stack

- **macOS App**: Swift 6, SwiftUI, GRDB (SQLite), ScreenCaptureKit, Speech Framework, MLX Swift, MLXVLM.
- **Web**: React 18, TypeScript, Webpack 5, pnpm.
- **Infrastructure**: Terraform, AWS (S3, CloudFront).
- **Models**: Gemma 4 E4B (via MLX).

## Building and Running

### macOS Application
- **Open Project**: `open TaskTrace.xcodeproj`
- **Build/Run**: Use Xcode (Command+R) or `xcodebuild`.
- **Tests**: Command+U in Xcode.
- **Dependencies**: Managed via Swift Package Manager (SPM).

### Web Project
- **Install**: `cd TaskTraceWeb && pnpm install`
- **Dev Server**: `pnpm dev`
- **Build**: `pnpm build`

### Infrastructure
- **Plan**: `cd Infra && terraform plan`
- **Apply**: `cd Infra && terraform apply`

## Development Conventions

### Architecture & State
- **Actors for State**: Avoid mutable state in classes. Use `actor` for thread-safe state management (see `TaskTraceDatabase` or `ActivityActor`).
- **Encapsulated Logic**: Functions should encapsulate logically separable units of business logic.
- **Avoid Helper Proliferation**: Prefer inline closures and destructured returns over creating many small helper functions unless they are needed for DRY or unit testing.
- **Knowledge Store Memory Rule**: Never retain corpus-scale knowledge state in memory. Do not cache all knowledge files, events, scanned file payloads, graph payloads, or similar data inside `KnowledgeGraphActor`, stores, or views.
- **Knowledge Data Access**: The database is the source of truth for knowledge data. Visualizations should load knowledge data lazily from the database through the knowledge store, and business logic that needs to inspect existing knowledge files, links, chunks, or events should query the database directly.

### Coding Style
- **Functional Programming**: Prefer `map`, `reduce`, and `filter` over `for` loops.
- **Minimal Defensive Programming**: Only use try/catch for unreliable external systems. Trust internal logic.
- **WebP Encoding**: Screenshots are stored as WebP (see `TaskTrace/CaptureMonitor.swift`).

### Testing
- **Atomic Tests**: Each test should have exactly one assertion.
- **Fixtures**: Use setup/fixtures to provide necessary state for tests (see `AGENTS.md` for examples).
- **Framework**: Uses the new Swift Testing framework.

## Key Upstream References
- [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)
- [MLXVLM Documentation](https://swiftpackageindex.com/ml-explore/mlx-swift-lm/main/documentation/mlxvlm)
