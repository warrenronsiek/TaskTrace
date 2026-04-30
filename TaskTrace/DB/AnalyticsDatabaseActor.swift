//
//  AnalyticsDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/11/26.
//

import Foundation
import GRDB

actor AnalyticsDatabaseActor {
    private let database: TaskTraceDatabase

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func activityAggregation(
        startDate: Date,
        endDate: Date
    ) async throws -> [ActivityAggregation] {
        try database.read { db in
            try ActivityAggregation.fetchAll(
                db,
                sql: """
                    WITH leads AS (
                        SELECT
                            start_time,
                            tags.name AS tag_name,
                            application,
                            CAST((
                                strftime('%s', LEAD(start_time)
                                    OVER (PARTITION BY DATE(start_time) ORDER BY start_time)
                                ) - strftime('%s', start_time)
                            ) AS INTEGER) AS duration
                        FROM activities
                        LEFT JOIN tags ON activities.tag_id = tags.id
                        WHERE DATE(start_time) BETWEEN DATE(?) AND DATE(?)
                    )
                    SELECT
                        DATE(start_time) AS dt,
                        tag_name,
                        SUM(duration) AS duration
                    FROM leads
                    WHERE application <> 'PAUSED'
                      AND application <> 'SLEEP'
                    GROUP BY DATE(start_time), tag_name
                    ORDER BY DATE(start_time) ASC, tag_name ASC
                    """,
                arguments: [
                    startDate.formatted(TaskTraceDatabase.sqlDateStyle),
                    endDate.formatted(TaskTraceDatabase.sqlDateStyle)
                ]
            )
        }
    }
}
