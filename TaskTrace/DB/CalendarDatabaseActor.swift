//
//  CalendarDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB

actor CalendarDatabaseActor {
    struct RenderingData: Sendable {
        let availableDates: [Date]
        let earliestVisibleMonth: Date?
    }

    private let database: TaskTraceDatabase

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func loadRenderingData(referenceDate: Date) async throws -> RenderingData {
        try database.read { db in
            let dates = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT DATE(start_time) AS dt
                    FROM activities
                    ORDER BY dt ASC
                    """
            )
            let availableDates = try (dates + [referenceDate.formatted(TaskTraceDatabase.sqlDateStyle)])
                .reduce(into: [Date]()) { partialResult, value in
                    let date = try TaskTraceDatabase.date(fromSQLDate: value)

                    if !partialResult.contains(date) {
                        partialResult.append(date)
                    }
                }
            let earliestVisibleMonth = availableDates
                .first(where: { $0 != Calendar(identifier: .gregorian).startOfDay(for: referenceDate) })
                .flatMap { Calendar(identifier: .gregorian).dateInterval(of: .month, for: $0)?.start }

            return RenderingData(
                availableDates: availableDates,
                earliestVisibleMonth: earliestVisibleMonth
            )
        }
    }
}
