#include "TaskTraceSQLiteVector.h"
#include "sqlite-vector-impl.h"

int taskTraceSQLiteVectorInitialize(sqlite3 *db) {
    return sqlite3_vector_init(db, NULL, NULL);
}
