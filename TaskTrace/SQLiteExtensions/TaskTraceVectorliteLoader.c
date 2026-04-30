#include "TaskTraceVectorliteLoader.h"
#include "../SQLiteCustom/TaskTraceSQLiteRuntime.h"

int taskTraceVectorliteInitialize(sqlite3 *db, const char *path, char **errorMessage) {
    int extensionLoadingEnabled = 0;
    int resultCode = sqlite3_db_config(
        db,
        SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION,
        1,
        &extensionLoadingEnabled
    );

    if (resultCode != SQLITE_OK) {
        return resultCode;
    }

    // Enable loading only for the duration of this call. We do not want a
    // permanently open extension-loading surface on application connections.
    resultCode = taskTraceSQLiteLoadExtension(db, path, 0, errorMessage);
    sqlite3_db_config(
        db,
        SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION,
        0,
        &extensionLoadingEnabled
    );
    return resultCode;
}

int taskTraceSQLiteSetDefensiveMode(sqlite3 *db, int enabled) {
    int previousValue = 0;
    return sqlite3_db_config(
        db,
        SQLITE_DBCONFIG_DEFENSIVE,
        enabled,
        &previousValue
    );
}
