#ifndef TASKTRACE_VECTORLITE_LOADER_H
#define TASKTRACE_VECTORLITE_LOADER_H

#include <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

int taskTraceVectorliteInitialize(sqlite3 *db, const char *path, char **errorMessage);
int taskTraceSQLiteSetDefensiveMode(sqlite3 *db, int enabled);

#ifdef __cplusplus
}
#endif

#endif
