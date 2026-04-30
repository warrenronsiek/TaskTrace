//
//  SearchProgressTests.swift
//  TaskTraceTests
//
//  Created by Codex on 3/26/26.
//

import Testing
@testable import TaskTrace

struct SearchProgressTests {
    @Test("idle progress is not visible")
    func idleProgressIsNotVisible() {
        #expect(SearchProgress.idle.isVisible == false)
    }

    @Test("finished progress remains visible")
    func finishedProgressRemainsVisible() {
        #expect(SearchProgress.finished.isVisible == true)
    }

    @Test("completed stages report completed status")
    func completedStagesReportCompletedStatus() {
        let progress = SearchProgress(
            activeStage: .secondPassKeywordize,
            completedStages: [.firstPassKeywordize, .firstPassSearch]
        )

        #expect(progress.status(for: .firstPassSearch) == .completed)
    }

    @Test("active stage reports active status")
    func activeStageReportsActiveStatus() {
        let progress = SearchProgress(
            activeStage: .secondPassKeywordize,
            completedStages: [.firstPassKeywordize, .firstPassSearch]
        )

        #expect(progress.status(for: .secondPassKeywordize) == .active)
    }

    @Test("future stages report pending status")
    func futureStagesReportPendingStatus() {
        let progress = SearchProgress(
            activeStage: .secondPassKeywordize,
            completedStages: [.firstPassKeywordize, .firstPassSearch]
        )

        #expect(progress.status(for: .secondPassSearch) == .pending)
    }
}
