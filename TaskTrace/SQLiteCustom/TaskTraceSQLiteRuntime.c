// TaskTrace ships one project-owned SQLite runtime instead of relying on the
// system libsqlite3 that happens to be present on the host. This guarantees:
//
// 1. FTS5 exists on every connection in every environment.
// 2. sqlite3_load_extension is available when we need to load vectorlite.
// 3. GRDB, sqlite-vector, and vectorlite all resolve symbols against the same
//    SQLite core, instead of accidentally mixing multiple runtimes.
//
// We are not reimplementing SQLite here. This file just compiles the official
// amalgamation with the features TaskTrace requires.
#define SQLITE_ENABLE_API_ARMOR 1
#define SQLITE_ENABLE_FTS3 1
#define SQLITE_ENABLE_FTS3_PARENTHESIS 1
#define SQLITE_ENABLE_FTS5 1
#define SQLITE_ENABLE_LOAD_EXTENSION 1
#define SQLITE_ENABLE_LOCKING_STYLE 1
#define SQLITE_ENABLE_RTREE 1
#define SQLITE_ENABLE_SNAPSHOT 1
#define SQLITE_ENABLE_UPDATE_DELETE_LIMIT 1
#define SQLITE_OMIT_AUTORESET 1
#define SQLITE_OMIT_BUILTIN_TEST 1
#define SQLITE_OS_UNIX 1
#define SQLITE_SYSTEM_MALLOC 1
#define SQLITE_THREADSAFE 2

#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#pragma clang diagnostic ignored "-Wsign-conversion"
#pragma clang diagnostic ignored "-Wimplicit-int-conversion"
#pragma clang diagnostic ignored "-Wimplicit-float-conversion"
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wambiguous-macro"
#pragma clang diagnostic ignored "-Wcomma"
#endif

#include "../../Vendor/SQLite/sqlite3.c"

#if defined(__clang__)
#pragma clang diagnostic pop
#endif

int taskTraceSQLiteLoadExtension(sqlite3 *db, const char *path, const char *entryPoint, char **errorMessage) {
    return sqlite3_load_extension(db, path, entryPoint, errorMessage);
}
