//
//  ActivityDatabaseActor.swift
//  TaskTrace
//
//  Created by Codex on 4/6/26.
//

import AppKit
import CryptoKit
import Foundation
import GRDB
import MLX
import OSLog
import WebP

nonisolated enum ActivityVectorDecodingError: Error {
    case invalidFloat32ByteCount(Int64, Int)
    case inconsistentFloat32Dimension(expected: Int, activityID: Int64, actual: Int)
}

actor ActivityDatabaseActor: Receiver {
    let database: TaskTraceDatabase
    private let logger = Logger(subsystem: "com.tasktrace.Tasktrace", category: "general")

    private enum OntologyAssignmentApplicationResult: Sendable {
        case assigned(ActivityOntologyAssignment)
        case preservedManual
        case missingLatestRun
        case missingCandidate
    }

    init(database: TaskTraceDatabase) {
        self.database = database
    }

    func receive(_ envelope: Envelope) async {
        switch envelope.message {
        case let event as ActivityCreated:
            logger.log(
                "activity-database-actor received activity-created sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activity.id, privacy: .public)"
            )

            do {
                try await saveActivity(event.activity)
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-created operation=save-activity activityID=\(event.activity.id, privacy: .public) application=\(event.activity.application, privacy: .public) screenshotCount=\(event.activity.screenshots.count, privacy: .public) summaryCharacters=\((event.activity.summary ?? "").count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityUpdated:
            logger.log(
                "activity-database-actor received activity-updated sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activity.id, privacy: .public)"
            )

            do {
                try await saveActivity(event.activity)
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-updated operation=save-activity activityID=\(event.activity.id, privacy: .public) application=\(event.activity.application, privacy: .public) screenshotCount=\(event.activity.screenshots.count, privacy: .public) summaryCharacters=\((event.activity.summary ?? "").count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityKeystrokesAppended:
            logger.log(
                "activity-database-actor received activity-keystrokes-appended sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) characters=\(event.text.count, privacy: .public)"
            )

            do {
                guard let record = try await loadActivityRecord(id: event.activityID) else {
                    return
                }

                try await updateActivityKeystrokes(
                    activityID: record.id,
                    keystrokes: (record.keystrokes ?? "") + event.text
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-keystrokes-appended operation=save-activity activityID=\(event.activityID, privacy: .public) appendedCharacters=\(event.text.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityMicrophoneAppended:
            logger.log(
                "activity-database-actor received activity-microphone-appended sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) characters=\(event.transcript.count, privacy: .public)"
            )

            do {
                guard let record = try await loadActivityRecord(id: event.activityID) else {
                    return
                }

                let existingMicrophone = record.microphone ?? ""
                let nextTranscript = event.transcript
                let microphone = existingMicrophone.isEmpty
                    ? nextTranscript
                    : "\(existingMicrophone) \(nextTranscript)"

                try await updateActivityMicrophone(
                    activityID: record.id,
                    microphone: microphone
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-microphone-appended operation=save-activity activityID=\(event.activityID, privacy: .public) appendedCharacters=\(event.transcript.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivitySummarized:
            logger.log(
                "activity-database-actor received activity-summarized sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activity.id, privacy: .public)"
            )

            do {
                try await updateActivitySummary(
                    activityID: event.activity.id,
                    summary: event.activity.summary
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-summarized operation=save-activity activityID=\(event.activity.id, privacy: .public) application=\(event.activity.application, privacy: .public) screenshotCount=\(event.activity.screenshots.count, privacy: .public) summaryCharacters=\((event.activity.summary ?? "").count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivitySummaryEmbedded:
            logger.log(
                "activity-database-actor received activity-summary-embedded sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) dimensions=\(event.vector.count, privacy: .public)"
            )

            do {
                try await persistActivitySummaryVector(
                    activityID: event.activityID,
                    vector: event.vector
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-summary-embedded operation=save-activity-summary-vector activityID=\(event.activityID, privacy: .public) dimensions=\(event.vector.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityUMAPed:
            logger.log(
                "activity-database-actor received activity-umaped sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) dimensions=\(event.vector.count, privacy: .public)"
            )

            do {
                try await saveActivitySummaryUMAPVector(
                    activityID: event.activityID,
                    vector: event.vector
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-umaped operation=save-activity-summary-umap-vector activityID=\(event.activityID, privacy: .public) dimensions=\(event.vector.count, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityKnowledgeEncoded:
            logger.log(
                "activity-database-actor received activity-knowledge-encoded sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) success=\(event.success, privacy: .public)"
            )

            guard event.success else {
                return
            }

            do {
                try await markActivityKnowledgeProcessed(
                    activityID: event.activityID,
                    processed: true
                )
                try await refreshOverviewKnowledgeProcessed(activityID: event.activityID)
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-knowledge-encoded operation=mark-activity-knowledge-processed activityID=\(event.activityID, privacy: .public) success=\(event.success, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityTagAssigned:
            logger.log(
                "activity-database-actor received activity-tag-assigned sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID, privacy: .public)"
            )

            do {
                try await updateActivityOntologyTag(
                    activityID: event.activityID,
                    tagID: event.tagID,
                    ontologyCandidateID: event.ontologyCandidateID
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-tag-assigned operation=save-activity activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityTagSet:
            logger.log(
                "activity-database-actor received activity-tag-set sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID.map(String.init) ?? "<nil>", privacy: .public)"
            )

            do {
                try await updateActivityManualTag(
                    activityID: event.activityID,
                    tagID: event.tagID
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-tag-set operation=save-activity activityID=\(event.activityID, privacy: .public) tagID=\(event.tagID.map(String.init) ?? "<nil>", privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ImageDescribed:
            logger.log(
                "activity-database-actor received image-described sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(event.screenshotID, privacy: .public)"
            )

            do {
                guard let record = try await loadScreenshotRecord(id: event.screenshotID),
                      record.description == nil else {
                    return
                }

                try await updateScreenshotDescription(
                    screenshotID: record.id,
                    description: event.description
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=image-described operation=update-screenshot-description screenshotID=\(event.screenshotID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ScreenshotTextRead:
            logger.log(
                "activity-database-actor received screenshot-text-read sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(event.screenshotID, privacy: .public)"
            )

            do {
                guard let record = try await loadScreenshotRecord(id: event.screenshotID),
                      record.ocrText == nil else {
                    return
                }

                try await updateScreenshotText(
                    screenshotID: record.id,
                    text: event.text
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=screenshot-text-read operation=update-screenshot-text screenshotID=\(event.screenshotID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ScreenshotSummarized:
            logger.log(
                "activity-database-actor received screenshot-summarized sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) screenshotID=\(event.screenshotID, privacy: .public)"
            )

            do {
                guard let record = try await loadScreenshotRecord(id: event.screenshotID),
                      record.summary == nil else {
                    return
                }

                try await updateScreenshotSummary(
                    screenshotID: record.id,
                    summary: event.summary
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=screenshot-summarized operation=update-screenshot-summary screenshotID=\(event.screenshotID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as OverviewTagSetRequested:
            logger.log(
                "activity-database-actor received overview-tag-set-requested sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) overviewID=\(event.overviewID, privacy: .public) tagID=\(event.tagID, privacy: .public)"
            )

            do {
                try await updateOverviewTagForActivities(
                    overviewID: event.overviewID,
                    tagID: event.tagID
                )
            } catch {
                logger.error(
                    "activity-database-actor failed event=overview-tag-set-requested operation=save-activities-for-overview overviewID=\(event.overviewID, privacy: .public) tagID=\(event.tagID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        case let event as ActivityDeleted:
            logger.log(
                "activity-database-actor received activity-deleted sender=\(envelope.sender?.uuidString ?? "<nil>", privacy: .public) activityID=\(event.activityID, privacy: .public)"
            )

            do {
                try await deleteActivityRecord(id: event.activityID)
            } catch {
                logger.error(
                    "activity-database-actor failed event=activity-deleted operation=delete-activity activityID=\(event.activityID, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        default:
            return
        }
    }

    private func saveActivity(_ activity: ActivityActor.Activity) async throws {
        logger.log(
            "activity-database-actor db-save operation=upsert-activity activityID=\(activity.id, privacy: .public) application=\(activity.application, privacy: .public) screenshotCount=\(activity.screenshots.count, privacy: .public) keystrokeCharacters=\(activity.keystrokes.count, privacy: .public) microphoneCharacters=\(activity.microphone.count, privacy: .public) summaryCharacters=\((activity.summary ?? "").count, privacy: .public) tagID=\(activity.tagID.map(String.init) ?? "<nil>", privacy: .public) overviewID=\(activity.overviewID.map(String.init) ?? "<nil>", privacy: .public)"
        )
        try await saveActivityRecord(ActivityInput(
            id: activity.id,
            startTime: activity.startTime,
            application: activity.application,
            keystrokes: activity.keystrokes,
            microphone: activity.microphone,
            summary: activity.summary,
            tagID: activity.tagID,
            jsonProperties: nil,
            overviewID: activity.overviewID
        ))
        try await refreshOverviewKnowledgeProcessed(activityID: activity.id)

        let screenshotPersistence = try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, image IS NOT NULL AS has_image
                    FROM screenshots
                    WHERE activity_id = ?
                    """,
                arguments: [activity.id]
            )
            .reduce(into: (existing: Set<Int64>(), withImage: Set<Int64>())) { partial, row in
                let screenshotID: Int64 = row["id"]
                let hasImage: Bool = row["has_image"]

                partial.existing.insert(screenshotID)

                if hasImage {
                    partial.withImage.insert(screenshotID)
                }
            }
        }
        let existingScreenshotIDs = screenshotPersistence.existing
        let currentScreenshotIDs = Set(activity.screenshots.map(\.id))

        for screenshot in activity.screenshots {
            let image = screenshotPersistence.withImage.contains(screenshot.id) ? nil : screenshot.image
            logger.log(
                "activity-database-actor db-save operation=upsert-screenshot activityID=\(activity.id, privacy: .public) screenshotID=\(screenshot.id, privacy: .public) hasImage=\((image != nil), privacy: .public) hasDescription=\((screenshot.description != nil), privacy: .public) hasText=\((screenshot.text != nil), privacy: .public) hasSummary=\((screenshot.summary != nil), privacy: .public) ignoreReason=\(screenshot.ignoreReason ?? "<nil>", privacy: .public)"
            )
            try await saveScreenshotRecord(activityID: activity.id, screenshot: ScreenshotInput(
                id: screenshot.id,
                image: image,
                timestamp: screenshot.timestamp,
                description: screenshot.description,
                text: screenshot.text,
                summary: screenshot.summary,
                ignoreReason: screenshot.ignoreReason,
                jsonProperties: nil
            ))
        }

        for screenshotID in existingScreenshotIDs.subtracting(currentScreenshotIDs) {
            logger.log(
                "activity-database-actor db-delete operation=delete-screenshot activityID=\(activity.id, privacy: .public) screenshotID=\(screenshotID, privacy: .public)"
            )
            try await deleteScreenshotRecord(id: screenshotID)
        }
    }

    func loadActivities(for date: Date) async throws -> [LoadedActivity] {
        let startOfDay = Calendar(identifier: .gregorian).startOfDay(for: date)
        let nextDay = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        let startSQL = startOfDay.formatted(TaskTraceDatabase.sqlTimestampStyle)
        let endSQL = nextDay.formatted(TaskTraceDatabase.sqlTimestampStyle)

        return try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT
                        a.id AS a_id,
                        a.start_time AS a_start_time,
                        a.application AS a_application,
                        a.keystrokes AS a_keystrokes,
                        a.microphone AS a_microphone,
                        a.summary AS a_summary,
                        a.tag_id AS a_tag_id,
                        a.tag_assignment_source AS a_tag_assignment_source,
                        a.ontology_candidate_id AS a_ontology_candidate_id,
                        a.overview_id AS a_overview_id,
                        a.overview_assignment_source AS a_overview_assignment_source,
                        a.goal_todo_id AS a_goal_todo_id,
                        a.goal_todo_assignment_source AS a_goal_todo_assignment_source,
                        a.goal_todo_assignment_score AS a_goal_todo_assignment_score,
                        s.id AS s_id,
                        s.ts AS s_ts,
                        s.description AS s_description,
                        s.ocr_text AS s_ocr_text,
                        s.summary AS s_summary,
                        s.ignore_reason AS s_ignore_reason
                    FROM activities a
                    LEFT JOIN screenshots s
                        ON a.id = s.activity_id
                        AND s.ts >= ?
                        AND s.ts < ?
                    WHERE a.start_time >= ?
                      AND a.start_time < ?
                    ORDER BY a.start_time ASC, s.ts ASC
                    """,
                arguments: [startSQL, endSQL, startSQL, endSQL]
            )
            .reduce(into: [Int64: LoadedActivity]()) { partialResult, row in
                let id: Int64 = row["a_id"]

                if partialResult[id] == nil {
                    partialResult[id] = LoadedActivity(
                        id: id,
                        startTime: try TaskTraceDatabase.date(fromSQLTimestamp: row["a_start_time"]),
                        application: row["a_application"],
                        keystrokes: row["a_keystrokes"],
                        microphone: row["a_microphone"],
                        summary: row["a_summary"],
                        tagID: row["a_tag_id"],
                        tagAssignmentSource: (row["a_tag_assignment_source"] as String?)
                            .flatMap(ActivityTagAssignmentSource.init(rawValue:)),
                        ontologyCandidateID: row["a_ontology_candidate_id"],
                        overviewAssignmentSource: (row["a_overview_assignment_source"] as String?)
                            .flatMap(OverviewAssignmentSource.init(rawValue:)),
                        overviewID: row["a_overview_id"],
                        goalTodoID: row["a_goal_todo_id"],
                        goalTodoAssignmentSource: (row["a_goal_todo_assignment_source"] as String?)
                            .flatMap(GoalTodoAssignmentSource.init(rawValue:)),
                        goalTodoAssignmentScore: row["a_goal_todo_assignment_score"],
                        screenshots: []
                    )
                }

                if let screenshotID: Int64 = row["s_id"] {
                    partialResult[id]?.screenshots.append(
                        LoadedScreenshot(
                            id: screenshotID,
                            image: nil,
                            timestamp: try TaskTraceDatabase.date(fromSQLTimestamp: row["s_ts"]),
                            description: row["s_description"],
                            text: row["s_ocr_text"],
                            summary: row["s_summary"],
                            ignoreReason: row["s_ignore_reason"]
                        )
                    )
                }
            }
            .values
            .sorted { $0.id < $1.id }
        }
    }

    func loadScreenshotImage(screenshotID: Int64) async throws -> Data? {
        try database.read { db in
            try Data.fetchOne(
                db,
                sql: """
                    SELECT image
                    FROM screenshots
                    WHERE id = ?
                    """,
                arguments: [screenshotID]
            )
        }
    }

    func loadActivitySummaryEmbeddingBatch() async throws -> ActivitySummaryEmbeddingBatch {
        try database.read { db in
            let vectors = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, summary_vector
                    FROM activities
                    WHERE summary_vector IS NOT NULL
                    ORDER BY id ASC
                    """
            )
            .map { row in
                let activityID: Int64 = row["id"]
                let vectorData: Data = row["summary_vector"]

                guard vectorData.count.isMultiple(of: MemoryLayout<Float>.stride) else {
                    throw ActivityVectorDecodingError.invalidFloat32ByteCount(
                        activityID,
                        vectorData.count
                    )
                }

                return (
                    activityID: activityID,
                    vectorData: vectorData,
                    vectorDimension: vectorData.count / MemoryLayout<Float>.stride
                )
            }

            guard let firstVector = vectors.first else {
                return ActivitySummaryEmbeddingBatch(
                    activityIDs: [],
                    vectorsData: Data(),
                    vectorCount: 0,
                    vectorDimension: 0
                )
            }

            guard let inconsistentVector = vectors.first(where: {
                $0.vectorDimension != firstVector.vectorDimension
            }) else {
                return ActivitySummaryEmbeddingBatch(
                    activityIDs: vectors.map(\.activityID),
                    vectorsData: vectors.reduce(
                        into: Data(capacity: vectors.reduce(0) { $0 + $1.vectorData.count })
                    ) {
                        $0.append($1.vectorData)
                    },
                    vectorCount: vectors.count,
                    vectorDimension: firstVector.vectorDimension
                )
            }

            throw ActivityVectorDecodingError.inconsistentFloat32Dimension(
                expected: firstVector.vectorDimension,
                activityID: inconsistentVector.activityID,
                actual: inconsistentVector.vectorDimension
            )
        }
    }

    func saveActivitySummaryUMAPBatch(_ batch: ActivitySummaryUMAPBatch) async throws {
        precondition(batch.activityIDs.count == batch.vectorCount)
        precondition(
            batch.vectorsData.count
                == batch.vectorCount * batch.vectorDimension * MemoryLayout<Float>.stride
        )

        let rowByteCount = batch.vectorDimension * MemoryLayout<Float>.stride

        try database.write { db in
            try zip(batch.activityIDs.indices, batch.activityIDs).forEach { index, activityID in
                let start = index * rowByteCount
                let end = start + rowByteCount

                try db.execute(
                    sql: """
                        UPDATE activities
                        SET summary_vector_umap = ?
                        WHERE id = ?
                        """,
                    arguments: [
                        batch.vectorsData.subdata(in: start..<end),
                        activityID
                    ]
                )
            }

            let placeholders = Array(repeating: "?", count: batch.activityIDs.count)
                .joined(separator: ", ")

            try db.execute(
                sql: """
                    UPDATE activities
                    SET summary_vector_umap = NULL
                    WHERE id NOT IN (\(placeholders))
                    """,
                arguments: StatementArguments(batch.activityIDs)
            )
        }
    }

    func clearActivitySummaryUMAPVectors() async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET summary_vector_umap = NULL
                    """
            )
        }
    }

    func markActivityKnowledgeProcessed(
        activityID: Int64,
        processed: Bool
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET knowledge_processed = ?
                    WHERE id = ?
                    """,
                arguments: [processed ? 1 : 0, activityID]
            )
        }
    }

    private func refreshOverviewKnowledgeProcessed(
        activityID: Int64
    ) async throws {
        try database.write { db in
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
                    WHERE id = (
                        SELECT overview_id
                        FROM activities
                        WHERE id = ?
                    )
                    """,
                arguments: [activityID]
            )
        }
    }

    func loadUnprocessedActivityKnowledgeRequests(
        dayStart: Date,
        dayEnd: Date,
        afterActivityID: Int64?,
        limit: Int
    ) async throws -> [ActivityKnowledgeEncodeRequested] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, summary
                    FROM activities
                    WHERE start_time >= ?
                      AND start_time < ?
                      AND summary IS NOT NULL
                      AND summary <> ''
                      AND knowledge_processed = 0
                      AND id > ?
                    ORDER BY id ASC
                    LIMIT ?
                    """,
                arguments: [
                    dayStart.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    dayEnd.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    afterActivityID ?? 0,
                    limit
                ]
            )
            .compactMap { row in
                guard let activityID: Int64 = row["id"],
                      let summary: String = row["summary"] else {
                    return nil
                }

                return ActivityKnowledgeEncodeRequested(
                    activityID: activityID,
                    summary: summary
                )
            }
        }
    }

    func loadActivityKnowledgeRebuildRequests(
        dayStart: Date,
        dayEnd: Date,
        afterActivityID: Int64?,
        limit: Int
    ) async throws -> [ActivityKnowledgeEncodeRequested] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, summary
                    FROM activities
                    WHERE start_time >= ?
                      AND start_time < ?
                      AND overview_id IS NOT NULL
                      AND summary IS NOT NULL
                      AND summary <> ''
                      AND id > ?
                    ORDER BY id ASC
                    LIMIT ?
                    """,
                arguments: [
                    dayStart.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    dayEnd.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    afterActivityID ?? 0,
                    limit
                ]
            )
            .compactMap { row in
                guard let activityID: Int64 = row["id"],
                      let summary: String = row["summary"] else {
                    return nil
                }

                return ActivityKnowledgeEncodeRequested(
                    activityID: activityID,
                    summary: summary
                )
            }
        }
    }

    private func loadActivityRecord(id: Int64) async throws -> ActivityRecord? {
        try database.read { db in
            try ActivityRecord.fetchOne(
                db,
                sql: "SELECT * FROM activities WHERE id = ?",
                arguments: [id]
            )
        }
    }

    private func loadScreenshotRecord(id: Int64) async throws -> ScreenshotRecord? {
        try database.read { db in
            try ScreenshotRecord.fetchOne(
                db,
                sql: "SELECT * FROM screenshots WHERE id = ?",
                arguments: [id]
            )
        }
    }

    func saveActivityRecord(_ activity: ActivityInput) async throws {
        let summaryHash = activity.summary
            .flatMap { $0.isEmpty ? nil : Self.sha256(for: $0) }
        try database.vectorAwareWrite { db in
            try db.execute(
                sql: """
                    INSERT INTO activities (
                        id,
                        start_time,
                        application,
                        keystrokes,
                        microphone,
                        summary,
                        summary_hash,
                        knowledge_processed,
                        tag_id,
                        json_properties,
                        overview_id
                    )
                    VALUES (
                        ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?
                    )
                    ON CONFLICT(id) DO UPDATE SET
                        start_time = COALESCE(excluded.start_time, activities.start_time),
                        application = COALESCE(excluded.application, activities.application),
                        keystrokes = COALESCE(excluded.keystrokes, activities.keystrokes),
                        microphone = COALESCE(excluded.microphone, activities.microphone),
                        summary = COALESCE(excluded.summary, activities.summary),
                        summary_hash = CASE
                            WHEN excluded.summary IS NULL THEN activities.summary_hash
                            ELSE excluded.summary_hash
                        END,
                        knowledge_processed = CASE
                            WHEN excluded.summary IS NULL THEN activities.knowledge_processed
                            WHEN excluded.summary = activities.summary THEN activities.knowledge_processed
                            ELSE 0
                        END,
                        summary_vector = CASE
                            WHEN excluded.summary IS NULL THEN activities.summary_vector
                            WHEN excluded.summary = activities.summary THEN activities.summary_vector
                            ELSE NULL
                        END,
                        summary_vector_umap = CASE
                            WHEN excluded.summary IS NULL THEN activities.summary_vector_umap
                            WHEN excluded.summary = activities.summary THEN activities.summary_vector_umap
                            ELSE NULL
                        END,
                        tag_id = COALESCE(excluded.tag_id, activities.tag_id),
                        json_properties = COALESCE(excluded.json_properties, activities.json_properties),
                        overview_id = COALESCE(excluded.overview_id, activities.overview_id)
                    """,
                arguments: [
                    activity.id,
                    activity.startTime.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    activity.application,
                    activity.keystrokes,
                    activity.microphone,
                    activity.summary,
                    summaryHash,
                    activity.tagID,
                    activity.jsonProperties,
                    activity.overviewID
                ]
            )
            try Self.syncActivitySummaryVectorIndex(in: db, activityID: activity.id)
        }
    }

    func saveScreenshotRecord(
        activityID: Int64,
        screenshot: ScreenshotInput
    ) async throws {
        let persistedImage: Data? = {
            guard let image = screenshot.image else {
                return nil
            }

            let decodedImage: CGImage? = {
                guard let nsImage = NSImage(data: image),
                      let tiffRepresentation = nsImage.tiffRepresentation,
                      let bitmapRepresentation = NSBitmapImageRep(data: tiffRepresentation) else {
                    return nil
                }

                return bitmapRepresentation.cgImage
                    ?? nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }()

            guard let decodedImage else {
                return image
            }

            let originalWidth = decodedImage.width
            let originalHeight = decodedImage.height
            let longestEdge = max(originalWidth, originalHeight)
            let scale = longestEdge > 1920
                ? Double(1920) / Double(longestEdge)
                : 1.0
            let width = max(1, Int((Double(originalWidth) * scale).rounded()))
            let height = max(1, Int((Double(originalHeight) * scale).rounded()))
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            return {
                var rgbaBytes = [UInt8](repeating: 0, count: height * bytesPerRow)

                guard let context = CGContext(
                    data: &rgbaBytes,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
                ) else {
                    return image
                }

                context.interpolationQuality = .high
                context.draw(decodedImage, in: CGRect(x: 0, y: 0, width: width, height: height))

                let configuration = WebPEncoderConfig.preset(.picture, quality: 80)
                let encoder = WebPEncoder()

                return rgbaBytes.withUnsafeMutableBytes { bytes in
                    guard let rgba = bytes.bindMemory(to: UInt8.self).baseAddress else {
                        return image
                    }

                    return try? encoder.encode(
                        RGBA: rgba,
                        config: configuration,
                        originWidth: width,
                        originHeight: height,
                        stride: bytesPerRow
                    )
                } ?? image
            }()
        }()

        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO screenshots (
                        id,
                        image,
                        ts,
                        description,
                        ocr_text,
                        summary,
                        description_vector,
                        ignore_reason,
                        json_properties,
                        activity_id
                    )
                    VALUES (?, ?, ?, ?, ?, ?, CASE WHEN ? IS NULL THEN NULL ELSE vector_as_f32(?) END, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        image = COALESCE(excluded.image, screenshots.image),
                        ts = excluded.ts,
                        description = excluded.description,
                        ocr_text = excluded.ocr_text,
                        summary = COALESCE(excluded.summary, screenshots.summary),
                        description_vector = COALESCE(excluded.description_vector, screenshots.description_vector),
                        ignore_reason = excluded.ignore_reason,
                        json_properties = excluded.json_properties,
                        activity_id = excluded.activity_id
                    """,
                arguments: [
                    screenshot.id,
                    persistedImage,
                    screenshot.timestamp.map { $0.formatted(TaskTraceDatabase.sqlTimestampStyle) },
                    screenshot.description,
                    screenshot.text,
                    screenshot.summary,
                    nil,
                    nil,
                    screenshot.ignoreReason,
                    screenshot.jsonProperties,
                    activityID
                ]
            )
        }
    }

    private func deleteActivityRecord(id: Int64) async throws {
        try database.vectorAwareWriteFlushing { db in
            try Self.deleteCurrentOntologyMembership(in: db, activityID: id)
            try db.execute(
                sql: "DELETE FROM \(TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName) WHERE rowid = ?",
                arguments: [id]
            )
            try db.execute(sql: "DELETE FROM activities WHERE id = ?", arguments: [id])
        }
    }

    private func deleteScreenshotRecord(id: Int64) async throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM screenshots WHERE id = ?", arguments: [id])
        }
    }

    func persistActivitySummaryVector(activityID: Int64, vector: [Float]) async throws {
        try database.vectorAwareWrite { db in
            try Self.persistActivitySummaryVector(
                in: db,
                activityID: activityID,
                vector: vector
            )
        }
    }

    func applyActivitySummaryEmbeddingToOntology(
        activityID: Int64,
        vector: [Float],
        k: Int = ActivityTagOntologyDefaults.neighborCount
    ) async throws -> ActivityOntologyAssignment? {
        let result = try database.vectorAwareWrite { db in
            try Self.persistActivitySummaryVector(
                in: db,
                activityID: activityID,
                vector: vector
            )
            return try Self.applyLatestOntologyAssignment(
                in: db,
                activityID: activityID,
                k: k
            )
        }

        switch result {
        case let .assigned(assignment):
            return assignment
        case .preservedManual:
            return nil
        case .missingLatestRun:
            logger.log(
                "activity-database-actor skipped ontology assignment because no latest run exists activityID=\(activityID, privacy: .public)"
            )
            return nil
        case .missingCandidate:
            logger.log(
                "activity-database-actor skipped ontology assignment because latest run has no matching candidate activityID=\(activityID, privacy: .public)"
            )
            return nil
        }
    }

    func applyLatestOntologyAssignments(
        activityIDs: [Int64],
        k: Int = ActivityTagOntologyDefaults.neighborCount
    ) async throws -> [ActivityOntologyAssignment] {
        guard !activityIDs.isEmpty else {
            return []
        }

        let results = try database.vectorAwareWrite { db in
            try activityIDs.sorted().map { activityID in
                (
                    activityID: activityID,
                    result: try Self.applyLatestOntologyAssignment(
                        in: db,
                        activityID: activityID,
                        k: k
                    )
                )
            }
        }

        results.forEach { entry in
            switch entry.result {
            case .assigned, .preservedManual:
                break
            case .missingLatestRun:
                logger.log(
                    "activity-database-actor skipped ontology assignment because no latest run exists activityID=\(entry.activityID, privacy: .public)"
                )
            case .missingCandidate:
                logger.log(
                    "activity-database-actor skipped ontology assignment because latest run has no matching candidate activityID=\(entry.activityID, privacy: .public)"
                )
            }
        }

        return results.compactMap { entry in
            if case let .assigned(assignment) = entry.result {
                assignment
            } else {
                nil
            }
        }
    }

    private nonisolated static func applyLatestOntologyAssignment(
        in db: Database,
        activityID: Int64,
        k: Int
    ) throws -> OntologyAssignmentApplicationResult {
        try Self.deleteCurrentOntologyMembership(in: db, activityID: activityID)

        let neighborhoodActivityIDs = try Self.loadActivityOntologyNeighborhoodIDs(
            in: db,
            activityID: activityID,
            k: k
        )

        try TaskTraceDatabaseBootstrap.upsertActivityOntologyEdges(
            on: db,
            activityIDs: neighborhoodActivityIDs
        )

        guard let latestRunID = try Self.loadLatestOntologyRunID(in: db) else {
            return .missingLatestRun
        }

        guard let assignment = try Self.resolveLatestOntologyAssignment(
            in: db,
            activityID: activityID,
            latestRunID: latestRunID
        ) else {
            return .missingCandidate
        }

        try db.execute(
            sql: """
                INSERT INTO activity_tag_ontology_candidate_activities (
                    candidate_id,
                    activity_id,
                    centrality_score
                )
                VALUES (?, ?, NULL)
                ON CONFLICT(candidate_id, activity_id) DO UPDATE SET
                    centrality_score = NULL
                """,
            arguments: [
                assignment.ontologyCandidateID,
                assignment.activityID
            ]
        )
        try Self.recomputeOntologyCandidate(
            in: db,
            candidateID: assignment.ontologyCandidateID
        )

        let currentTagAssignmentSource = try Self.loadActivityTagAssignmentSource(
            in: db,
            activityID: activityID
        )

        try db.execute(
            sql: """
                UPDATE activities
                SET
                    ontology_candidate_id = ?,
                    tag_id = CASE
                        WHEN tag_assignment_source = ? THEN tag_id
                        ELSE ?
                    END,
                    tag_assignment_source = CASE
                        WHEN tag_assignment_source = ? THEN tag_assignment_source
                        ELSE ?
                    END
                WHERE id = ?
                """,
            arguments: [
                assignment.ontologyCandidateID,
                ActivityTagAssignmentSource.manual.rawValue,
                assignment.tagID,
                ActivityTagAssignmentSource.manual.rawValue,
                ActivityTagAssignmentSource.ontology.rawValue,
                activityID
            ]
        )

        guard currentTagAssignmentSource != .manual else {
            return .preservedManual
        }

        return .assigned(assignment)
    }

    func loadActivityTagOntologyRefreshSnapshot() async throws -> ActivityTagOntologyRefreshSnapshot {
        try database.vectorAwareRead { db in
            let activities = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, summary, summary_vector
                    FROM activities
                    WHERE summary_vector IS NOT NULL
                      AND summary IS NOT NULL
                      AND summary <> ''
                    ORDER BY id ASC
                    """
            )
            .map { row in
                ActivityTagOntologyActivitySnapshot(
                    id: row["id"],
                    summary: row["summary"],
                    summaryVector: row["summary_vector"]
                )
            }
            let edges = try ActivityEdgeRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM activity_edges
                    ORDER BY first_activity_id ASC, second_activity_id ASC
                    """
            )
            guard let latestRun = try Self.loadLatestOntologyRun(in: db) else {
                return ActivityTagOntologyRefreshSnapshot(
                    activities: activities,
                    edges: edges,
                    latestRun: nil,
                    latestCandidates: []
                )
            }

            let candidates = try ActivityTagOntologyCandidateRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM activity_tag_ontology_candidates
                    WHERE run_id = ?
                    ORDER BY id ASC
                    """,
                arguments: [latestRun.id]
            )
            let candidateIDs = candidates.map(\.id)
            let tagIDs = Array(Set(candidates.map(\.tagID))).sorted()

            let memberships = candidateIDs.isEmpty
                ? [ActivityTagOntologyCandidateActivityRecord]()
                : try ActivityTagOntologyCandidateActivityRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM activity_tag_ontology_candidate_activities
                        WHERE candidate_id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: candidateIDs.count)))
                        ORDER BY candidate_id ASC, activity_id ASC
                        """,
                    arguments: StatementArguments(candidateIDs)
                )
            let tags = tagIDs.isEmpty
                ? [TagRecord]()
                : try TagRecord.fetchAll(
                    db,
                    sql: """
                        SELECT *
                        FROM tags
                        WHERE id IN (\(TaskTraceDatabase.databaseQuestionMarks(count: tagIDs.count)))
                        ORDER BY id ASC
                        """,
                    arguments: StatementArguments(tagIDs)
                )
            let membershipsByCandidateID = Dictionary(grouping: memberships, by: \.candidateID)
            let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })

            return ActivityTagOntologyRefreshSnapshot(
                activities: activities,
                edges: edges,
                latestRun: latestRun,
                latestCandidates: candidates.map {
                    ActivityTagOntologyCandidateSnapshot(
                        candidate: $0,
                        tag: tagsByID[$0.tagID],
                        memberActivityIDs: (membershipsByCandidateID[$0.id] ?? [])
                            .map(\.activityID)
                    )
                }
            )
        }
    }

    func loadActivityOntologyCatchUpSnapshot(
        day: Date,
        calendar: Calendar = .current
    ) async throws -> ActivityOntologyCatchUpSnapshot {
        try database.read { db in
            let dayStart = calendar.startOfDay(for: day)
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let records = try ActivityRecord.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM activities
                    WHERE start_time >= ?
                      AND start_time < ?
                    ORDER BY start_time ASC, id ASC
                    """,
                arguments: [
                    dayStart.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    nextDayStart.formatted(TaskTraceDatabase.sqlTimestampStyle)
                ]
            )

            return ActivityOntologyCatchUpSnapshot(
                latestRunID: try Self.loadLatestOntologyRunID(in: db),
                activitiesMissingEmbeddings: records
                    .filter { !($0.summary?.isEmpty ?? true) && $0.summaryVector == nil }
                    .map {
                        ActivityActor.Activity(
                            id: $0.id,
                            application: $0.application,
                            startTime: $0.startTime,
                            keystrokes: $0.keystrokes ?? "",
                            microphone: $0.microphone ?? "",
                            summary: $0.summary,
                            overviewID: $0.overviewID,
                            overviewAssignmentSource: $0.overviewAssignmentSource.flatMap(OverviewAssignmentSource.init(rawValue:)),
                            tagID: $0.tagID,
                            tagAssignmentSource: $0.tagAssignmentSource.flatMap(ActivityTagAssignmentSource.init(rawValue:)),
                            ontologyCandidateID: $0.ontologyCandidateID,
                            screenshots: []
                        )
                    },
                activityIDsMissingTags: records
                    .filter { $0.summaryVector != nil && $0.tagID == nil }
                    .map(\.id),
                activityIDsMissingOverviews: records
                    .filter { $0.tagID != nil && $0.overviewID == nil }
                    .map(\.id)
            )
        }
    }

    func publishActivityTagOntologyRun(
        _ runInput: ActivityTagOntologyRunInput,
        tags: [TagInput]
    ) async throws {
        try database.vectorAwareWrite { db in
            try tags.forEach { tag in
                try db.execute(
                    sql: """
                        INSERT INTO tags (
                            id,
                            name,
                            create_date,
                            description,
                            delete_date,
                            json_properties,
                            origin_kind,
                            generated_name,
                            generated_description,
                            name_is_user_edited,
                            description_is_user_edited
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            name = COALESCE(excluded.name, tags.name),
                            description = COALESCE(excluded.description, tags.description),
                            create_date = COALESCE(tags.create_date, excluded.create_date),
                            delete_date = COALESCE(excluded.delete_date, tags.delete_date),
                            json_properties = COALESCE(excluded.json_properties, tags.json_properties),
                            origin_kind = COALESCE(excluded.origin_kind, tags.origin_kind),
                            generated_name = COALESCE(excluded.generated_name, tags.generated_name),
                            generated_description = COALESCE(excluded.generated_description, tags.generated_description),
                            name_is_user_edited = COALESCE(excluded.name_is_user_edited, tags.name_is_user_edited),
                            description_is_user_edited = COALESCE(excluded.description_is_user_edited, tags.description_is_user_edited)
                        """,
                    arguments: [
                        tag.id,
                        tag.name,
                        (tag.createDate ?? runInput.createdAt).formatted(TaskTraceDatabase.sqlDateStyle),
                        tag.description,
                        tag.deleteDate.map { $0.formatted(TaskTraceDatabase.sqlDateStyle) },
                        tag.jsonProperties,
                        tag.originKind,
                        tag.generatedName,
                        tag.generatedDescription,
                        tag.nameIsUserEdited,
                        tag.descriptionIsUserEdited
                    ]
                )
            }

            try db.execute(
                sql: """
                    INSERT INTO activity_tag_ontology_runs (
                        id,
                        created_at,
                        previous_run_id,
                        k_neighbors,
                        leiden_resolution,
                        leiden_theta,
                        continuity_alpha,
                        continuity_beta,
                        continuity_gamma
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    runInput.runID,
                    runInput.createdAt.formatted(TaskTraceDatabase.sqlTimestampStyle),
                    runInput.previousRunID,
                    runInput.kNeighbors,
                    runInput.leidenResolution,
                    runInput.leidenTheta,
                    runInput.continuityAlpha,
                    runInput.continuityBeta,
                    runInput.continuityGamma
                ]
            )

            try runInput.candidates.forEach { candidate in
                try db.execute(
                    sql: """
                        INSERT INTO activity_tag_ontology_candidates (
                            id,
                            run_id,
                            tag_id,
                            predecessor_candidate_id,
                            name,
                            summary,
                            centroid_vector,
                            member_count,
                            member_overlap,
                            centroid_similarity,
                            continuity_similarity
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        candidate.candidateID,
                        runInput.runID,
                        candidate.tagID,
                        candidate.predecessorCandidateID,
                        candidate.name,
                        candidate.summary,
                        candidate.centroidVector,
                        candidate.memberActivityIDs.count,
                        candidate.memberOverlap,
                        candidate.centroidSimilarity,
                        candidate.continuitySimilarity
                    ]
                )

                try candidate.memberActivityIDs
                    .sorted()
                    .forEach { activityID in
                        try db.execute(
                            sql: """
                                INSERT INTO activity_tag_ontology_candidate_activities (
                                    candidate_id,
                                    activity_id,
                                    centrality_score
                                )
                                VALUES (?, ?, ?)
                                """,
                            arguments: [
                                candidate.candidateID,
                                activityID,
                                candidate.centralityScoreByActivityID[activityID]
                            ]
                        )
                    }
            }

            try db.execute(
                sql: """
                    UPDATE activities
                    SET ontology_candidate_id = NULL
                    """
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        tag_id = NULL,
                        tag_assignment_source = NULL
                    WHERE tag_assignment_source = ?
                    """,
                arguments: [ActivityTagAssignmentSource.ontology.rawValue]
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET ontology_candidate_id = (
                        SELECT candidate_activities.candidate_id
                        FROM activity_tag_ontology_candidate_activities candidate_activities
                        JOIN activity_tag_ontology_candidates candidates
                          ON candidates.id = candidate_activities.candidate_id
                        WHERE candidates.run_id = ?
                          AND candidate_activities.activity_id = activities.id
                        LIMIT 1
                    )
                    WHERE EXISTS (
                        SELECT 1
                        FROM activity_tag_ontology_candidate_activities candidate_activities
                        JOIN activity_tag_ontology_candidates candidates
                          ON candidates.id = candidate_activities.candidate_id
                        WHERE candidates.run_id = ?
                          AND candidate_activities.activity_id = activities.id
                    )
                    """,
                arguments: [runInput.runID, runInput.runID]
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        tag_id = (
                            SELECT candidates.tag_id
                            FROM activity_tag_ontology_candidates candidates
                            WHERE candidates.id = activities.ontology_candidate_id
                            LIMIT 1
                        ),
                        tag_assignment_source = ?
                    WHERE ontology_candidate_id IS NOT NULL
                      AND COALESCE(tag_assignment_source, '') != ?
                    """,
                arguments: [
                    ActivityTagAssignmentSource.ontology.rawValue,
                    ActivityTagAssignmentSource.manual.rawValue
                ]
            )
        }
    }

    private func saveActivitySummaryUMAPVector(activityID: Int64, vector: [Float]) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET summary_vector_umap = ?
                    WHERE id = ?
                    """,
                arguments: [
                    vector.withUnsafeBytes { Data($0) },
                    activityID
                ]
            )
        }
    }

    private func updateActivityKeystrokes(
        activityID: Int64,
        keystrokes: String
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET keystrokes = ?
                    WHERE id = ?
                    """,
                arguments: [keystrokes, activityID]
            )
        }
    }

    private func updateActivityMicrophone(
        activityID: Int64,
        microphone: String
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET microphone = ?
                    WHERE id = ?
                    """,
                arguments: [microphone, activityID]
            )
        }
    }

    private func updateActivitySummary(
        activityID: Int64,
        summary: String?
    ) async throws {
        let summaryHash = summary
            .flatMap { $0.isEmpty ? nil : Self.sha256(for: $0) }
        try database.vectorAwareWrite { db in
            try Self.deleteCurrentOntologyMembership(in: db, activityID: activityID)
            try db.execute(
                sql: """
                    DELETE FROM activity_edges
                    WHERE first_activity_id = ?
                       OR second_activity_id = ?
                    """,
                arguments: [
                    activityID,
                    activityID
                ]
            )
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        summary = ?,
                        summary_hash = ?,
                        knowledge_processed = 0,
                        ontology_candidate_id = NULL,
                        tag_id = CASE
                            WHEN tag_assignment_source = ? THEN NULL
                            ELSE tag_id
                        END,
                        tag_assignment_source = CASE
                            WHEN tag_assignment_source = ? THEN NULL
                            ELSE tag_assignment_source
                        END,
                        overview_id = CASE
                            WHEN overview_assignment_source = ? THEN NULL
                            ELSE overview_id
                        END,
                        overview_assignment_source = CASE
                            WHEN overview_assignment_source = ? THEN NULL
                            ELSE overview_assignment_source
                        END,
                        summary_vector = NULL,
                        summary_vector_umap = NULL
                    WHERE id = ?
                """,
                arguments: [
                    summary,
                    summaryHash,
                    ActivityTagAssignmentSource.ontology.rawValue,
                    ActivityTagAssignmentSource.ontology.rawValue,
                    OverviewAssignmentSource.ontology.rawValue,
                    OverviewAssignmentSource.ontology.rawValue,
                    activityID
                ]
            )
            try Self.syncActivitySummaryVectorIndex(in: db, activityID: activityID)
        }

        try await refreshOverviewKnowledgeProcessed(activityID: activityID)
    }

    private nonisolated static func syncActivitySummaryVectorIndex(
        in db: Database,
        activityID: Int64
    ) throws {
        try TaskTraceDatabaseBootstrap.markActivitySummaryVectorIndexDirty(
            on: db,
            activityID: activityID
        )
        try TaskTraceDatabaseBootstrap.syncActivitySummaryVectorIndexEntry(
            on: db,
            activityID: activityID
        )
    }

    private func updateActivityOntologyTag(
        activityID: Int64,
        tagID: Int64,
        ontologyCandidateID: Int64?
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        tag_id = ?,
                        tag_assignment_source = ?,
                        ontology_candidate_id = ?
                    WHERE id = ?
                      AND COALESCE(tag_assignment_source, '') != ?
                    """,
                arguments: [
                    tagID,
                    ActivityTagAssignmentSource.ontology.rawValue,
                    ontologyCandidateID,
                    activityID,
                    ActivityTagAssignmentSource.manual.rawValue
                ]
            )
        }
    }

    private func updateActivityManualTag(
        activityID: Int64,
        tagID: Int64?
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        tag_id = ?,
                        tag_assignment_source = CASE
                            WHEN ? IS NULL THEN NULL
                            ELSE ?
                        END
                    WHERE id = ?
                    """,
                arguments: [
                    tagID,
                    tagID,
                    ActivityTagAssignmentSource.manual.rawValue,
                    activityID
                ]
            )
        }
    }

    private func updateOverviewTagForActivities(
        overviewID: Int64,
        tagID: Int64?
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE activities
                    SET
                        tag_id = ?,
                        tag_assignment_source = CASE
                            WHEN ? IS NULL THEN NULL
                            ELSE ?
                        END,
                        overview_assignment_source = ?
                    WHERE overview_id = ?
                """,
                arguments: [
                    tagID,
                    tagID,
                    ActivityTagAssignmentSource.manual.rawValue,
                    OverviewAssignmentSource.manual.rawValue,
                    overviewID
                ]
            )
        }
    }

    private func updateActivitiesOverview(
        activityIDs: [Int64],
        overviewID: Int64
    ) async throws {
        let uniqueActivityIDs = Array(Set(activityIDs)).sorted()

        guard !uniqueActivityIDs.isEmpty else {
            return
        }

        try database.write { db in
            let placeholders = uniqueActivityIDs.map { _ in "?" }.joined(separator: ", ")
            try db.execute(
                sql: """
                    UPDATE activities
                    SET overview_id = ?
                    WHERE id IN (\(placeholders))
                    """,
                arguments: StatementArguments([overviewID] + uniqueActivityIDs)
            )
        }
    }

    private func updateScreenshotDescription(
        screenshotID: Int64,
        description: String
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshots
                    SET description = ?
                    WHERE id = ?
                    """,
                arguments: [description, screenshotID]
            )
        }
    }

    private func updateScreenshotText(
        screenshotID: Int64,
        text: String
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshots
                    SET ocr_text = ?
                    WHERE id = ?
                    """,
                arguments: [text, screenshotID]
            )
        }
    }

    private func updateScreenshotSummary(
        screenshotID: Int64,
        summary: String
    ) async throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE screenshots
                    SET summary = ?
                    WHERE id = ?
                    """,
                arguments: [summary, screenshotID]
            )
        }
    }

    nonisolated private static func sha256(for text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func vectorJSONString(_ vector: [Float]) throws -> String {
        String(
            decoding: try JSONEncoder().encode(vector),
            as: UTF8.self
        )
    }

    private nonisolated static func persistActivitySummaryVector(
        in db: Database,
        activityID: Int64,
        vector: [Float]
    ) throws {
        try db.execute(
            sql: """
                UPDATE activities
                SET summary_vector = vector_as_f32(?)
                WHERE id = ?
                """,
            arguments: [
                try vectorJSONString(vector),
                activityID
            ]
        )
        try syncActivitySummaryVectorIndex(in: db, activityID: activityID)
    }

    private nonisolated static func loadLatestOntologyRunID(
        in db: Database
    ) throws -> Int64? {
        try Int64.fetchOne(
            db,
            sql: """
                SELECT id
                FROM activity_tag_ontology_runs
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """
        )
    }

    private nonisolated static func loadLatestOntologyRun(
        in db: Database
    ) throws -> ActivityTagOntologyRunRecord? {
        try ActivityTagOntologyRunRecord.fetchOne(
            db,
            sql: """
                SELECT *
                FROM activity_tag_ontology_runs
                ORDER BY created_at DESC, id DESC
                LIMIT 1
                """
        )
    }

    private nonisolated static func loadActivityTagAssignmentSource(
        in db: Database,
        activityID: Int64
    ) throws -> ActivityTagAssignmentSource? {
        let rawValue = try String.fetchOne(
            db,
            sql: """
                SELECT tag_assignment_source
                FROM activities
                WHERE id = ?
                """,
            arguments: [activityID]
        )

        return rawValue.flatMap(ActivityTagAssignmentSource.init(rawValue:))
    }

    private nonisolated static func loadActivityOntologyNeighborhoodIDs(
        in db: Database,
        activityID: Int64,
        k: Int
    ) throws -> [Int64] {
        let neighborIDs = try Int64.fetchAll(
            db,
            sql: """
                WITH query_vector AS (
                    SELECT vector_from_json(vector_to_json(summary_vector)) AS embedding
                    FROM activities
                    WHERE id = ?
                      AND summary_vector IS NOT NULL
                )
                SELECT rowid
                FROM \(TaskTraceDatabaseBootstrap.activitySummaryVectorIndexTableName)
                WHERE knn_search(
                    embedding,
                    knn_param((SELECT embedding FROM query_vector), ?)
                )
                  AND rowid != ?
                ORDER BY distance ASC, rowid ASC
                """,
            arguments: [
                activityID,
                k + 1,
                activityID
            ]
        )

        return [activityID] + Array(neighborIDs.prefix(k))
    }

    private nonisolated static func deleteCurrentOntologyMembership(
        in db: Database,
        activityID: Int64
    ) throws {
        guard let latestRunID = try loadLatestOntologyRunID(in: db) else {
            return
        }

        let candidateIDs = try Int64.fetchAll(
            db,
            sql: """
                SELECT candidate_activities.candidate_id
                FROM activity_tag_ontology_candidate_activities candidate_activities
                JOIN activity_tag_ontology_candidates candidates
                  ON candidates.id = candidate_activities.candidate_id
                WHERE candidate_activities.activity_id = ?
                  AND candidates.run_id = ?
                ORDER BY candidate_activities.candidate_id ASC
                """,
            arguments: [
                activityID,
                latestRunID
            ]
        )

        guard !candidateIDs.isEmpty else {
            return
        }

        try db.execute(
            sql: """
                DELETE FROM activity_tag_ontology_candidate_activities
                WHERE activity_id = ?
                  AND candidate_id IN (
                      SELECT id
                      FROM activity_tag_ontology_candidates
                      WHERE run_id = ?
                  )
                """,
            arguments: [
                activityID,
                latestRunID
            ]
        )

        try Array(Set(candidateIDs)).sorted().forEach {
            try recomputeOntologyCandidate(in: db, candidateID: $0)
        }
    }

    private nonisolated static func resolveLatestOntologyAssignment(
        in db: Database,
        activityID: Int64,
        latestRunID: Int64
    ) throws -> ActivityOntologyAssignment? {
        let row = try Row.fetchOne(
            db,
            sql: """
                WITH activity_vector AS (
                    SELECT summary_vector AS embedding
                    FROM activities
                    WHERE id = ?
                      AND summary_vector IS NOT NULL
                ),
                incident_edges AS (
                    SELECT
                        CASE
                            WHEN first_activity_id = ? THEN second_activity_id
                            ELSE first_activity_id
                        END AS neighbor_activity_id,
                        weight
                    FROM activity_edges
                    WHERE first_activity_id = ?
                       OR second_activity_id = ?
                ),
                candidate_scores AS (
                    SELECT
                        candidates.id AS candidate_id,
                        candidates.tag_id AS tag_id,
                        COALESCE(SUM(incident_edges.weight), 0.0) AS total_weight
                    FROM activity_tag_ontology_candidates candidates
                    LEFT JOIN activity_tag_ontology_candidate_activities candidate_activities
                      ON candidate_activities.candidate_id = candidates.id
                    LEFT JOIN incident_edges
                      ON incident_edges.neighbor_activity_id = candidate_activities.activity_id
                    WHERE candidates.run_id = ?
                    GROUP BY candidates.id, candidates.tag_id
                ),
                edge_assignment AS (
                    SELECT candidate_id, tag_id, total_weight
                    FROM candidate_scores
                    WHERE total_weight > 0
                    ORDER BY total_weight DESC, candidate_id ASC
                    LIMIT 1
                ),
                centroid_assignment AS (
                    SELECT
                        candidates.id AS candidate_id,
                        candidates.tag_id AS tag_id,
                        MAX(
                            0.0,
                            1.0 - vector_distance(
                                (SELECT embedding FROM activity_vector),
                                candidates.centroid_vector,
                                'cosine'
                            )
                        ) AS total_weight
                    FROM activity_tag_ontology_candidates candidates
                    WHERE candidates.run_id = ?
                      AND candidates.centroid_vector IS NOT NULL
                      AND EXISTS (SELECT 1 FROM activity_vector)
                    ORDER BY total_weight DESC, candidates.id ASC
                    LIMIT 1
                )
                SELECT candidate_id, tag_id, total_weight
                FROM edge_assignment
                UNION ALL
                SELECT candidate_id, tag_id, total_weight
                FROM centroid_assignment
                WHERE NOT EXISTS (SELECT 1 FROM edge_assignment)
                LIMIT 1
                """,
            arguments: [
                activityID,
                activityID,
                activityID,
                activityID,
                latestRunID,
                latestRunID
            ]
        )

        guard let row else {
            return nil
        }

        return ActivityOntologyAssignment(
            activityID: activityID,
            tagID: row["tag_id"],
            ontologyCandidateID: row["candidate_id"]
        )
    }

    private nonisolated static func recomputeOntologyCandidate(
        in db: Database,
        candidateID: Int64
    ) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT
                    activities.id AS activity_id,
                    activities.summary_vector AS summary_vector
                FROM activity_tag_ontology_candidate_activities candidate_activities
                JOIN activities
                  ON activities.id = candidate_activities.activity_id
                WHERE candidate_activities.candidate_id = ?
                  AND activities.summary_vector IS NOT NULL
                ORDER BY activities.id ASC
                """,
            arguments: [candidateID]
        )

        guard let firstVectorData = rows.first?["summary_vector"] as Data? else {
            try db.execute(
                sql: """
                    UPDATE activity_tag_ontology_candidates
                    SET
                        centroid_vector = NULL,
                        member_count = 0
                    WHERE id = ?
                    """,
                arguments: [candidateID]
            )
            return
        }

        guard firstVectorData.count.isMultiple(of: MemoryLayout<Float>.stride) else {
            throw ActivityVectorDecodingError.invalidFloat32ByteCount(candidateID, firstVectorData.count)
        }

        let vectorDimension = firstVectorData.count / MemoryLayout<Float>.stride
        let vectorsData = try rows.reduce(
            into: Data(capacity: rows.count * firstVectorData.count)
        ) { partial, row in
            let activityID: Int64 = row["activity_id"]
            let vectorData: Data = row["summary_vector"]

            guard vectorData.count == firstVectorData.count else {
                throw ActivityVectorDecodingError.inconsistentFloat32Dimension(
                    expected: vectorDimension,
                    activityID: activityID,
                    actual: vectorData.count / MemoryLayout<Float>.stride
                )
            }

            partial.append(vectorData)
        }
        let centroid = mean(
            MLXArray(
                vectorsData,
                [rows.count, vectorDimension],
                type: Float.self
            ),
            axis: 0
        )
        let centroidData = centroid.asArray(Float.self)
            .withUnsafeBytes { Data($0) }

        try db.execute(
            sql: """
                UPDATE activity_tag_ontology_candidates
                SET
                    centroid_vector = ?,
                    member_count = ?
                WHERE id = ?
                """,
            arguments: [
                centroidData,
                rows.count,
                candidateID
            ]
        )
    }
}
