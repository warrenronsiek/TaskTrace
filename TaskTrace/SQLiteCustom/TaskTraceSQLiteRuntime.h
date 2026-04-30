#ifndef TASKTRACE_SQLITE_RUNTIME_H
#define TASKTRACE_SQLITE_RUNTIME_H

#include <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

int taskTraceSQLiteLoadExtension(sqlite3 *db, const char *path, const char *entryPoint, char **errorMessage);

#ifdef __cplusplus
}
#endif

#endif
