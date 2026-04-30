# Search

This module owns the user-facing search flow in the macOS app.

## Runtime Flow

Search is intentionally staged so the UI can show useful partial results while
more expensive AI work continues:

1. `SearchStore` trims and submits the user query.
2. `TaskTraceSearchService` extracts FTS-friendly keywords with
   `SearchKeywordizer`.
3. `SearchDatabaseActor` searches SQLite FTS tables and returns result trees.
4. The first pass is published to the UI.
5. The service extracts keywords from the first matched snippets and runs a
   second expanded search.
6. AI reranking scores matched overview, activity, and screenshot nodes.
7. A streamed search summary is generated from the ranked documents.

## Main Files

- `SearchView.swift`: SwiftUI search interface.
- `SearchStore.swift`: main-actor UI state, progress stages, and cancellation.
- `TaskTraceSearchService.swift`: staged retrieval, reranking, and summary orchestration.
- `SearchKeywordizer.swift`: NaturalLanguage-based keyword extraction and FTS query construction.
- `TaskTrace/DB/SearchDatabaseActor.swift`: database-side result tree retrieval.

## SQLite Search Indexes

Search uses FTS5 tables created by `TaskTrace/DB/DatabaseBootstrap.swift`:

- `activity_fts`
- `screenshot_fts`
- `overview_fts`

Those tables index activity text, screenshot description/OCR text, and overview
summary text. GRDB manages the FTS synchronization triggers.

## Vector Support

The app has two vector-related SQLite integrations:

- `TaskTrace/SQLiteVector/`: statically linked `sqlite-vector` functions.
- `AppResources/SQLiteExtensions/vectorlite.dylib`: bundled vectorlite extension used by vector-aware database paths.

SQLite extension registration is connection-scoped. Keep initialization inside
the database connection setup rather than moving it to global app startup.

## Tests

Search-related coverage is spread across:

- `TaskTraceTests/DatabaseTests.swift`
- `TaskTraceTests/SearchKeywordizerTests.swift`
- `TaskTraceTests/SearchProgressTests.swift`
- `TaskTraceTests/SearchStoreTests.swift`
- tests for the AI actors that provide reranking and summary generation

When changing search ranking or retrieval behavior, prefer tests that assert
observable result ordering or progress-state behavior rather than implementation
details.
