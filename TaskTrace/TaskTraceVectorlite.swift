import Foundation
import GRDB
import SQLite3

private final class TaskTraceVectorliteBundleLocator {}

enum TaskTraceVectorlite {
    nonisolated static func initialize(on db: Database) throws {
        guard let sqliteConnection = db.sqliteConnection else {
            throw DatabaseError(
                resultCode: .SQLITE_MISUSE,
                message: "SQLite connection unavailable for vectorlite initialization."
            )
        }

        // We look in both app-bundle locations and the checked-out source tree.
        // The source-tree fallback keeps tests and local CLI invocations working
        // when the app bundle has not been produced yet, while the bundle paths
        // are what shipping builds use at runtime.
        let bundle = Bundle(for: TaskTraceVectorliteBundleLocator.self)
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let sourceDirectoryURL = sourceFileURL.deletingLastPathComponent()
        let projectRootURL = sourceDirectoryURL.deletingLastPathComponent()
        let candidateURLs = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("vectorlite.dylib"),
            Bundle.main.resourceURL?.appendingPathComponent("vectorlite.dylib"),
            Bundle.main.resourceURL?.appendingPathComponent("SQLiteExtensions/vectorlite.dylib"),
            bundle.privateFrameworksURL?.appendingPathComponent("vectorlite.dylib"),
            bundle.resourceURL?.appendingPathComponent("vectorlite.dylib"),
            bundle.resourceURL?.appendingPathComponent("SQLiteExtensions/vectorlite.dylib"),
            projectRootURL.appendingPathComponent("AppResources/SQLiteExtensions/vectorlite.dylib")
        ].compactMap { $0 }

        guard let extensionURL = candidateURLs.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw DatabaseError(
                resultCode: .SQLITE_CANTOPEN,
                message: "Could not locate bundled vectorlite.dylib for vector-aware SQLite initialization."
            )
        }

        let loaderURL = {
            let pathExtension = extensionURL.pathExtension.lowercased()
            // sqlite3_load_extension retries known platform suffixes on Unix.
            // Passing a full ".dylib" filename can therefore degrade into
            // ".../vectorlite.dylib.dylib" on the fallback path. Hand SQLite
            // the canonical basename and let it append the platform suffix.
            return pathExtension == "dylib"
                ? extensionURL.deletingPathExtension()
                : extensionURL
        }()

        var loadErrorMessage: UnsafeMutablePointer<Int8>?
        let loadResult = loaderURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return SQLITE_CANTOPEN
            }

            // The C shim is responsible for enabling extension loading on the
            // live sqlite3 connection, calling into the active runtime's
            // sqlite3_load_extension symbol, and then disabling extension
            // loading again before control returns to Swift.
            return taskTraceVectorliteInitialize(sqliteConnection, path, &loadErrorMessage)
        }

        guard loadResult == SQLITE_OK else {
            let errorMessage = loadErrorMessage.map { String(cString: $0) } ?? "vectorlite load failed."

            if let loadErrorMessage {
                sqlite3_free(loadErrorMessage)
            }

            throw DatabaseError(
                resultCode: ResultCode(rawValue: loadResult),
                message: errorMessage
            )
        }
    }
}
