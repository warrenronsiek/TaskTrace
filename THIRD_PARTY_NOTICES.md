# Third-Party Notices

TaskTrace vendors or depends on third-party software and model artifacts. This
file is a release hygiene index, not a substitute for each upstream license.

## Vendored Runtime Code

- `Vendor/vectorlite`: SQLite vector-search extension. See
  `Vendor/vectorlite/LICENSE`.
- `Vendor/mlx-swift-lm`: MLX Swift language and VLM runtime. See
  `Vendor/mlx-swift-lm/LICENSE`.

## Swift Package Dependencies

Dependency metadata lives in
`TaskTrace.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
Review upstream licenses before each public release, especially for:

- Sparkle
- GRDB
- swift-markdown
- swift-sdk
- MijickCalendarView
- Swift-WebP and libwebp
- mlx-swift and mlx-swift-lm

## JavaScript Dependencies

JavaScript dependency metadata lives in:

- `package-lock.json` / `pnpm-lock.yaml`
- `TaskTraceWeb/package.json` and `TaskTraceWeb/pnpm-lock.yaml`
- `TaskTraceWebView/package.json` and lockfiles
- `BrowserPlugin/package.json` and `BrowserPlugin/package-lock.json`

Run the package-manager license audit appropriate to each package before a
tagged public release.

## Bundled Model Artifacts

The app bundle includes local model artifacts under `AppResources/LocalModels`.
As of the April 28, 2026 release-hygiene pass, the visible Hugging Face model
cards for these bundled or conversion-source models reported Apache-2.0:

- `mlx-community/Qwen3.5-4B-OptiQ-4bit`
- `mlx-community/Qwen3.5-0.8B-OptiQ-4bit`
- `mlx-community/gemma-4-e2b-it-4bit`
- `Qwen/Qwen3-Embedding-0.6B`
- `Qwen/Qwen3-Reranker-0.6B`

Model licenses and acceptable-use terms can change independently from this
repository. Re-check upstream model cards before publishing binaries or source
snapshots that include model weights.
