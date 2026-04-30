import Foundation
import GRDB
import SQLite3

enum TaskTraceSQLiteVector {
    nonisolated static func initialize(on db: Database) throws {
        guard let sqliteConnection = db.sqliteConnection else {
            throw DatabaseError(resultCode: .SQLITE_MISUSE, message: "SQLite connection unavailable for sqlite-vector initialization.")
        }

        let resultCode = taskTraceSQLiteVectorInitialize(sqliteConnection)

        guard resultCode == SQLITE_OK else {
            throw DatabaseError(
                resultCode: ResultCode(rawValue: resultCode),
                message: "sqlite-vector initialization failed."
            )
        }
    }
}
