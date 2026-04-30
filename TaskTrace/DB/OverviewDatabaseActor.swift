//
//  OverviewDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import Foundation
import GRDB
import OSLog

nonisolated struct OntologyOverviewRefreshKey: Hashable, Sendable {
    let day: Date
    let tagID: Int64
}

nonisolated struct OntologyOverviewSummaryKey: Hashable, Sendable {
    let day: Date
    let overviewID: Int64
}

nonisolated struct OntologyOverviewSummaryActivity: Equatable, Sendable {
    let id: Int64
    let startTime: Date
    let summary: String
}

nonisolated struct OntologyOverviewSummarySnapshot: Equatable, Sendable {
    let key: OntologyOverviewSummaryKey
    let overview: OverviewRecord?
    let activityIDs: [Int64]
    let activities: [OntologyOverviewSummaryActivity]
}

actor OverviewDatabaseActor: Receiver {
    private let database: TaskTraceDatabase
    private let logger = Logger(subsystem: "com.tasktrace.Tasktrace", category: "general")

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as OverviewEditedDurationSetRequested:
            logger.log(
                "overview-database-actor received overview-edited-duration-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public)"
            )

            do {
                try await updateOverviewEditedDuration(
                    overviewID: event.overviewID,
                    editedDuration: event.duration
                )
            } catch {
                logger.error(
                    "overview-database-actor failed event=overview-edited-duration-set-requested operation=save-overview overviewID=\(event.overviewID, privacy: .public) duration=\(event.duration, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as OverviewTitleSetRequested:
            logger.log(
                "overview-database-actor received overview-title-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public)"
            )

            do {
                try await updateOverviewTitle(
                    overviewID: event.overviewID,
                    title: event.title.isEmpty ? nil : event.title
                )
            } catch {
                logger.error(
                    "overview-database-actor failed event=overview-title-set-requested operation=save-overview overviewID=\(event.overviewID, privacy: .public) title=\(event.title, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as OverviewSummarySetRequested:
            logger.log(
                "overview-database-actor received overview-summary-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public)"
            )

            do {
                try await updateOverviewSummary(
                    overviewID: event.overviewID,
                    summary: event.summary.isEmpty ? nil : event.summary
                )
            } catch {
                logger.error(
                    "overview-database-actor failed event=overview-summary-set-requested operation=save-overview overviewID=\(event.overviewID, privacy: .public) summaryCharacters=\(event.summary.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as OverviewTagSetRequested:
            logger.log(
                "overview-database-actor received overview-tag-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public) tagID=\(event.tagID, privacy: .public)"
            )

            do {
                try await updateOverviewTag(
                    overviewID: event.overviewID,
                    tagID: event.tagID
                )
            } catch {
                logger.error(
                    "overview-database-actor failed event=overview-tag-set-requested operation=save-overview overviewID=\(event.overviewID, privacy: .public) tagID=\(event.tagID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as OverviewMergeResolved:
            logger.log(
                "overview-database-actor received overview-merge-resolved sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) mergedOverviewID=\(event.mergedOverviewID, privacy: .public)"
            )

            do {
                logger.log(
                    "overview-database-actor db-save event=overview-merge-resolved operation=merge-overviews mergedOverviewID=\(event.mergedOverviewID, privacy: .public) firstOverviewID=\(event.firstOverview.id, privacy: .public) secondOverviewID=\(event.secondOverview.id, privacy: .public) activityCount=\(event.activityIDs.count, privacy: .public)"
                )
                try await mergeOverviews(
                    OverviewInput(
                        id: event.mergedOverviewID,
                        title: event.decision.title ?? event.firstOverview.title ?? event.secondOverview.title,
                        summary: event.decision.summary ?? event.firstOverview.summary ?? event.secondOverview.summary,
                        jsonProperties: nil,
                        editedDuration: event.firstDuration + event.secondDuration,
                        tagID: event.firstOverview.tagID == event.secondOverview.tagID ? event.firstOverview.tagID : nil
                    ),
                    replacing: [event.firstOverview.id, event.secondOverview.id]
                )
            } catch {
                logger.error(
                    "overview-database-actor failed event=overview-merge-resolved operation=merge-overviews mergedOverviewID=\(event.mergedOverviewID, privacy: .public) firstOverviewID=\(event.firstOverview.id, privacy: .public) secondOverviewID=\(event.secondOverview.id, privacy: .public) activityCount=\(event.activityIDs.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        default:
            return
        }
    }

    func loadOverviews(for date: Date) async throws -> [LoadedOverview] {
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: date)
        let daySQL = startOfDay.formatted(TaskTraceDatabase.sqlDateStyle)

        return try database.read { db in
            try LoadedOverview.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT
                        o.id AS id,
                        o.title AS title,
                        o.summary AS summary,
                        o.edited_duration AS edited_duration,
                        o.tag_id AS tag_id,
                        o.origin_kind AS origin_kind,
                        o.generated_title AS generated_title,
                        o.generated_summary AS generated_summary,
                        o.title_is_user_edited AS title_is_user_edited,
                        o.summary_is_user_edited AS summary_is_user_edited
                    FROM overviews o
                    INNER JOIN activities a ON a.overview_id = o.id
                    WHERE DATE(a.start_time) = DATE(?)
                    ORDER BY o.id ASC
                    """,
                arguments: [daySQL]
            )
        }
    }

    func loadOntologyOverviewRefreshKey(
        activityID: Int64,
        tagID: Int64
    ) async throws -> OntologyOverviewRefreshKey? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT start_time
                    FROM activities
                    WHERE id = ?
                      AND tag_id = ?
                      AND COALESCE(overview_assignment_source, '') != ?
                    """,
                arguments: [
                    activityID,
                    tagID,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            ) else {
                return nil
            }

            return OntologyOverviewRefreshKey(
                day: Calendar(identifier: .gregorian).startOfDay(
                    for: try TaskTraceDatabase.date(fromSQLTimestamp: row["start_time"])
                ),
                tagID: tagID
            )
        }
    }

    func loadOntologyOverviewRefreshKeys() async throws -> [OntologyOverviewRefreshKey] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    WITH active_days AS (
                        SELECT DISTINCT DATE(start_time) AS day_start
                        FROM activities
                        WHERE COALESCE(overview_assignment_source, '') != ?
                    )
                    SELECT DISTINCT day_start, tag_id
                    FROM (
                        SELECT
                            DATE(start_time) AS day_start,
                            tag_id
                        FROM activities
                        WHERE tag_id IS NOT NULL
                          AND COALESCE(overview_assignment_source, '') != ?
                        UNION
                        SELECT
                            bindings.day_start AS day_start,
                            bindings.tag_id AS tag_id
                        FROM overview_day_tag_bindings bindings
                        JOIN active_days
                          ON active_days.day_start = bindings.day_start
                    )
                    ORDER BY day_start ASC, tag_id ASC
                    """,
                arguments: [
                    OverviewAssignmentSource.legacy.rawValue,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            )
            .map { row in
                OntologyOverviewRefreshKey(
                    day: try TaskTraceDatabase.date(fromSQLDate: row["day_start"]),
                    tagID: row["tag_id"]
                )
            }
        }
    }

    @discardableResult
    func ensureOntologyOverviewAssignment(
        key: OntologyOverviewRefreshKey,
        newOverviewID: Int64
    ) async throws -> OntologyOverviewSummaryKey? {
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: key.day)
        let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let daySQL = startOfDay.formatted(TaskTraceDatabase.sqlDateStyle)
        let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
        let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)

        return try database.write { db in
            let bindingRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT overview_id, binding_source
                    FROM overview_day_tag_bindings
                    WHERE day_start = DATE(?)
                      AND tag_id = ?
                    LIMIT 1
                    """,
                arguments: [daySQL, key.tagID]
            )
            let boundOverviewID: Int64? = bindingRow?["overview_id"]
            let bindingSource = (bindingRow?["binding_source"] as String?)
                .flatMap(OverviewBindingSource.init(rawValue:))
                ?? .auto
            let overviewID = boundOverviewID ?? newOverviewID
            let existingOverview = try OverviewRecord.fetchOne(
                db,
                sql: "SELECT * FROM overviews WHERE id = ?",
                arguments: [overviewID]
            )
            let activityIDArguments = (
                bindingSource == .manual && boundOverviewID != nil
                    ? [
                        startSQL,
                        endSQL,
                        key.tagID,
                        boundOverviewID,
                        OverviewAssignmentSource.legacy.rawValue
                    ]
                    : [
                        startSQL,
                        endSQL,
                        key.tagID,
                        OverviewAssignmentSource.legacy.rawValue
                    ]
            ) as [(any DatabaseValueConvertible)?]
            let activityIDs = try Int64.fetchAll(
                db,
                sql: bindingSource == .manual && boundOverviewID != nil
                    ? """
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND (
                              tag_id = ?
                              OR overview_id = ?
                          )
                          AND COALESCE(overview_assignment_source, '') != ?
                        ORDER BY start_time ASC, id ASC
                        """
                    : """
                        SELECT id
                        FROM activities
                        WHERE start_time >= ?
                          AND start_time < ?
                          AND tag_id = ?
                          AND COALESCE(overview_assignment_source, '') != ?
                        ORDER BY start_time ASC, id ASC
                        """,
                arguments: StatementArguments(activityIDArguments)
            )

            guard !activityIDs.isEmpty else {
                guard (bindingRow?["binding_source"] as String?) == OverviewBindingSource.auto.rawValue else {
                    return nil
                }

                try db.execute(
                    sql: """
                        DELETE FROM overview_day_tag_bindings
                        WHERE day_start = DATE(?)
                          AND tag_id = ?
                        """,
                    arguments: [daySQL, key.tagID]
                )

                if let boundOverviewID {
                    let overviewActivityCount = try Int.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*)
                            FROM activities
                            WHERE overview_id = ?
                            """,
                        arguments: [boundOverviewID]
                    ) ?? 0
                    let bindingCount = try Int.fetchOne(
                        db,
                        sql: """
                            SELECT COUNT(*)
                            FROM overview_day_tag_bindings
                            WHERE overview_id = ?
                            """,
                        arguments: [boundOverviewID]
                    ) ?? 0

                    if overviewActivityCount == 0,
                       bindingCount == 0 {
                        try db.execute(
                            sql: "DELETE FROM overviews WHERE id = ?",
                            arguments: [boundOverviewID]
                        )
                    }
                }

                return nil
            }

            let previousOverviewIDs = try Int64.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT overview_id
                    FROM activities
                    WHERE id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: activityIDs.count)))
                      AND overview_id IS NOT NULL
                      AND COALESCE(overview_assignment_source, '') != ?
                    """,
                arguments: StatementArguments(activityIDs + [OverviewAssignmentSource.legacy.rawValue])
            )

            try Self.upsertOverview(
                in: db,
                overview: OverviewInput(
                    id: overviewID,
                    title: existingOverview?.title,
                    summary: existingOverview?.summary,
                    jsonProperties: existingOverview?.jsonProperties,
                    editedDuration: existingOverview?.editedDuration,
                    tagID: bindingSource == .manual
                        ? (existingOverview?.tagID ?? key.tagID)
                        : key.tagID,
                    originKind: (bindingSource == .manual ? OverviewOriginKind.manual : OverviewOriginKind.ontology).rawValue,
                    generatedTitle: existingOverview?.generatedTitle,
                    generatedSummary: existingOverview?.generatedSummary,
                    titleIsUserEdited: existingOverview?.titleIsUserEdited,
                    summaryIsUserEdited: existingOverview?.summaryIsUserEdited
                )
            )
            try db.execute(
                sql: """
                    INSERT INTO overview_day_tag_bindings (
                        day_start,
                        tag_id,
                        overview_id,
                        binding_source
                    )
                    VALUES (DATE(?), ?, ?, ?)
                    ON CONFLICT(day_start, tag_id) DO UPDATE SET
                        overview_id = excluded.overview_id,
                        binding_source = excluded.binding_source
                    """,
                arguments: [
                    daySQL,
                    key.tagID,
                    overviewID,
                    bindingSource.rawValue
                ]
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        overview_id = ?,
                        overview_assignment_source = ?
                    WHERE start_time >= ?
                      AND start_time < ?
                      AND tag_id = ?
                      AND COALESCE(overview_assignment_source, '') != ?
                    """,
                arguments: [
                    overviewID,
                    (bindingSource == .manual ? OverviewAssignmentSource.manual : OverviewAssignmentSource.ontology).rawValue,
                    startSQL,
                    endSQL,
                    key.tagID,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            )

            try Self.refreshOverviewKnowledgeProcessed(
                in: db,
                overviewIDs: Array(Set(previousOverviewIDs + [overviewID]))
            )

            return OntologyOverviewSummaryKey(
                day: startOfDay,
                overviewID: overviewID
            )
        }
    }

    func loadOntologyOverviewSummarySnapshot(
        key: OntologyOverviewSummaryKey
    ) async throws -> OntologyOverviewSummarySnapshot {
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: key.day)
        let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
        let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)

        return try database.read { db in
            let overview = try OverviewRecord.fetchOne(
                db,
                sql: "SELECT * FROM overviews WHERE id = ?",
                arguments: [key.overviewID]
            )
            let activityIDs = try Int64.fetchAll(
                db,
                sql: """
                    SELECT id
                    FROM activities
                    WHERE start_time >= ?
                      AND start_time < ?
                      AND overview_id = ?
                      AND COALESCE(overview_assignment_source, '') != ?
                    ORDER BY start_time ASC, id ASC
                    """,
                arguments: [
                    startSQL,
                    endSQL,
                    key.overviewID,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            )
            let activities = try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        id,
                        start_time,
                        summary
                    FROM activities
                    WHERE start_time >= ?
                      AND start_time < ?
                      AND overview_id = ?
                      AND summary IS NOT NULL
                      AND summary <> ''
                      AND COALESCE(overview_assignment_source, '') != ?
                    ORDER BY start_time ASC, id ASC
                    """,
                arguments: [
                    startSQL,
                    endSQL,
                    key.overviewID,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            )
            .map {
                OntologyOverviewSummaryActivity(
                    id: $0["id"],
                    startTime: try TaskTraceDatabase.date(fromSQLTimestamp: $0["start_time"]),
                    summary: $0["summary"]
                )
            }

            return OntologyOverviewSummarySnapshot(
                key: key,
                overview: overview,
                activityIDs: activityIDs,
                activities: activities
            )
        }
    }

    func applyOntologyOverviewGeneratedText(
        overviewID: Int64,
        generatedTitle: String,
        generatedSummary: String
    ) async throws {
        try database.write { db in
            guard let existingOverview = try OverviewRecord.fetchOne(
                db,
                sql: "SELECT * FROM overviews WHERE id = ?",
                arguments: [overviewID]
            ) else {
                return
            }

            let nextTitle = existingOverview.titleIsUserEdited
                ? (existingOverview.title ?? generatedTitle)
                : generatedTitle
            let nextSummary = existingOverview.summaryIsUserEdited
                ? (existingOverview.summary ?? generatedSummary)
                : generatedSummary

            try Self.upsertOverview(
                in: db,
                overview: OverviewInput(
                    id: overviewID,
                    title: nextTitle,
                    summary: nextSummary,
                    jsonProperties: existingOverview.jsonProperties,
                    editedDuration: existingOverview.editedDuration,
                    tagID: existingOverview.tagID,
                    originKind: existingOverview.originKind,
                    generatedTitle: generatedTitle,
                    generatedSummary: generatedSummary,
                    titleIsUserEdited: existingOverview.titleIsUserEdited,
                    summaryIsUserEdited: existingOverview.summaryIsUserEdited
                )
            )

            try Self.refreshOverviewKnowledgeProcessed(
                in: db,
                overviewIDs: [overviewID]
            )
        }
    }

    func saveOverviewRecord(_ overview: OverviewInput) async throws {
        try database.write { db in
            try Self.upsertOverview(in: db, overview: overview)
        }
    }

    private func updateOverviewEditedDuration(
        overviewID: Int64,
        editedDuration: Int
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE overviews
                    SET edited_duration = ?
                    WHERE id = ?
                    """,
                arguments: [editedDuration, overviewID]
            )
        }
    }

    private func updateOverviewTitle(
        overviewID: Int64,
        title: String?
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE overviews
                    SET
                        title = ?,
                        title_is_user_edited = 1
                    WHERE id = ?
                    """,
                arguments: [title, overviewID]
            )
        }
    }

    private func updateOverviewSummary(
        overviewID: Int64,
        summary: String?
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE overviews
                    SET
                        summary = ?,
                        summary_is_user_edited = 1
                    WHERE id = ?
                    """,
                arguments: [summary, overviewID]
            )
        }
    }

    private func updateOverviewTag(
        overviewID: Int64,
        tagID: Int64?
    ) async throws {
        try database.write { db in
            let dayStarts = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT DATE(start_time)
                    FROM activities
                    WHERE overview_id = ?
                      AND COALESCE(overview_assignment_source, '') != ?
                    ORDER BY DATE(start_time) ASC
                    """,
                arguments: [
                    overviewID,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            )
            try db.execute(
                sql: """
                    UPDATE overviews
                    SET
                        tag_id = ?,
                        origin_kind = ?
                    WHERE id = ?
                    """,
                arguments: [
                    tagID,
                    OverviewOriginKind.manual.rawValue,
                    overviewID
                ]
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET overview_assignment_source = ?
                    WHERE overview_id = ?
                      AND COALESCE(overview_assignment_source, '') != ?
                    """,
                arguments: [
                    OverviewAssignmentSource.manual.rawValue,
                    overviewID,
                    OverviewAssignmentSource.legacy.rawValue
                ]
            )

            guard !dayStarts.isEmpty else {
                return
            }

            let placeholders = dayStarts.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: """
                    DELETE FROM overview_day_tag_bindings
                    WHERE overview_id = ?
                      AND day_start IN (\(placeholders))
                    """,
                arguments: StatementArguments([overviewID] + dayStarts)
            )

            guard let tagID else {
                return
            }

            try dayStarts.forEach { dayStart in
                try db.execute(
                    sql: """
                        INSERT INTO overview_day_tag_bindings (
                            day_start,
                            tag_id,
                            overview_id,
                            binding_source
                        )
                        VALUES (DATE(?), ?, ?, ?)
                        ON CONFLICT(day_start, tag_id) DO UPDATE SET
                            overview_id = excluded.overview_id,
                            binding_source = excluded.binding_source
                        """,
                    arguments: [
                        dayStart,
                        tagID,
                        overviewID,
                        OverviewBindingSource.manual.rawValue
                    ]
                )
            }
        }
    }

    private func mergeOverviews(
        _ mergedOverview: OverviewInput,
        replacing sourceOverviewIDs: [Int64]
    ) async throws {
        let uniqueSourceOverviewIDs = Array(Set(sourceOverviewIDs)).sorted()

        try database.write { db in
            let mergedDayTagRows = uniqueSourceOverviewIDs.isEmpty
                ? [Row]()
                : try Row.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT
                            DATE(start_time) AS day_start,
                            tag_id
                        FROM activities
                        WHERE overview_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: uniqueSourceOverviewIDs.count)))
                          AND tag_id IS NOT NULL
                          AND COALESCE(overview_assignment_source, '') != ?
                        ORDER BY day_start ASC, tag_id ASC
                        """,
                    arguments: StatementArguments(uniqueSourceOverviewIDs + [OverviewAssignmentSource.legacy.rawValue])
                )
            try Self.upsertOverview(
                in: db,
                overview: OverviewInput(
                    id: mergedOverview.id,
                    title: mergedOverview.title,
                    summary: mergedOverview.summary,
                    jsonProperties: mergedOverview.jsonProperties,
                    editedDuration: mergedOverview.editedDuration,
                    tagID: mergedOverview.tagID,
                    originKind: OverviewOriginKind.manual.rawValue,
                    generatedTitle: mergedOverview.title,
                    generatedSummary: mergedOverview.summary
                )
            )

            if !uniqueSourceOverviewIDs.isEmpty {
                let placeholders = uniqueSourceOverviewIDs.map { _ in "?" }.joined(separator: ", ")
                try db.execute(
                    sql: """
                        UPDATE activities
                        SET
                            overview_id = ?,
                            overview_assignment_source = CASE
                                WHEN COALESCE(overview_assignment_source, '') = ? THEN overview_assignment_source
                                ELSE ?
                            END
                        WHERE overview_id IN (\(placeholders))
                        """,
                    arguments: StatementArguments(
                        ([
                            mergedOverview.id,
                            OverviewAssignmentSource.legacy.rawValue,
                            OverviewAssignmentSource.manual.rawValue
                        ] + uniqueSourceOverviewIDs) as [(any DatabaseValueConvertible)?]
                    )
                )
                try db.execute(
                    sql: """
                        DELETE FROM overview_day_tag_bindings
                        WHERE overview_id IN (\(placeholders))
                        """,
                    arguments: StatementArguments(uniqueSourceOverviewIDs)
                )
                try mergedDayTagRows.forEach { row in
                    try db.execute(
                        sql: """
                            INSERT INTO overview_day_tag_bindings (
                                day_start,
                                tag_id,
                                overview_id,
                                binding_source
                            )
                            VALUES (DATE(?), ?, ?, ?)
                            ON CONFLICT(day_start, tag_id) DO UPDATE SET
                                overview_id = excluded.overview_id,
                                binding_source = excluded.binding_source
                            """,
                        arguments: [
                            row["day_start"],
                            row["tag_id"],
                            mergedOverview.id,
                            OverviewBindingSource.manual.rawValue
                        ]
                    )
                }
                try db.execute(
                    sql: "DELETE FROM overviews WHERE id IN (\(placeholders))",
                    arguments: StatementArguments(uniqueSourceOverviewIDs)
                )
            }

            try Self.refreshOverviewKnowledgeProcessed(
                in: db,
                overviewIDs: [mergedOverview.id]
            )
        }
    }

    private nonisolated static func upsertOverview(
        in db: Database,
        overview: OverviewInput
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO overviews (
                    id,
                    title,
                    summary,
                    summary_vector,
                    json_properties,
                    edited_duration,
                    tag_id,
                    origin_kind,
                    generated_title,
                    generated_summary,
                    title_is_user_edited,
                    summary_is_user_edited
                )
                VALUES (?, ?, ?, CASE WHEN ? IS NULL THEN NULL ELSE vector_as_f32(?) END, ?, ?, ?, ?, ?, ?, COALESCE(?, 0), COALESCE(?, 0))
                ON CONFLICT(id) DO UPDATE SET
                    title = COALESCE(excluded.title, overviews.title),
                    summary = COALESCE(excluded.summary, overviews.summary),
                    summary_vector = COALESCE(excluded.summary_vector, overviews.summary_vector),
                    json_properties = COALESCE(excluded.json_properties, overviews.json_properties),
                    edited_duration = COALESCE(excluded.edited_duration, overviews.edited_duration),
                    tag_id = COALESCE(excluded.tag_id, overviews.tag_id),
                    origin_kind = COALESCE(excluded.origin_kind, overviews.origin_kind),
                    generated_title = COALESCE(excluded.generated_title, overviews.generated_title),
                    generated_summary = COALESCE(excluded.generated_summary, overviews.generated_summary),
                    title_is_user_edited = COALESCE(excluded.title_is_user_edited, overviews.title_is_user_edited),
                    summary_is_user_edited = COALESCE(excluded.summary_is_user_edited, overviews.summary_is_user_edited)
                """,
            arguments: [
                overview.id,
                overview.title,
                overview.summary,
                nil,
                nil,
                overview.jsonProperties,
                overview.editedDuration,
                overview.tagID,
                overview.originKind,
                overview.generatedTitle,
                overview.generatedSummary,
                overview.titleIsUserEdited,
                overview.summaryIsUserEdited
            ]
        )
    }

    private nonisolated static func refreshOverviewKnowledgeProcessed(
        in db: Database,
        overviewIDs: [Int64]
    ) throws {
        let uniqueOverviewIDs = Array(Set(overviewIDs)).sorted()

        guard !uniqueOverviewIDs.isEmpty else {
            return
        }

        let placeholders = uniqueOverviewIDs.map { _ in "?" }.joined(separator: ", ")
        try db.execute(
            sql: """
                UPDATE overviews
                SET knowledge_processed = CASE
                    WHEN EXISTS (
                        SELECT 1
                        FROM activities
                        WHERE activities.overview_id = overviews.id
                    ) AND NOT EXISTS (
                        SELECT 1
                        FROM activities
                        WHERE activities.overview_id = overviews.id
                          AND (
                              activities.summary IS NULL
                              OR activities.summary = ''
                              OR activities.knowledge_processed = 0
                          )
                    ) THEN 1
                    ELSE 0
                END
                WHERE id IN (\(placeholders))
                """,
            arguments: StatementArguments(uniqueOverviewIDs)
        )
    }
}
