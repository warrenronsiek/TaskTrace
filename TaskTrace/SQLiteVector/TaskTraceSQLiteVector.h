#ifndef TASKTRACE_SQLITE_VECTOR_H
#define TASKTRACE_SQLITE_VECTOR_H

#include <sqlite3.h>

#ifdef __cplusplus
extern "C" {
#endif

int taskTraceSQLiteVectorInitialize(sqlite3 *db);

#ifdef __cplusplus
}
#endif

#endif
