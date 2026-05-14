import Testing
@testable import TaskTrace

struct GoalsTimelineGeometryTests {
    @Test("time zero aligns to todo zero")
    func timeZeroAlignsToTodoZero() {
        let geometry = GoalsTimelineGeometry(height: 200, maxDuration: 3_600)

        #expect(geometry.timeY(duration: 0) == geometry.zeroY)
    }

    @Test("max duration aligns to chart top")
    func maxDurationAlignsToChartTop() {
        let geometry = GoalsTimelineGeometry(height: 200, maxDuration: 3_600)

        #expect(geometry.timeY(duration: 3_600) == 0)
    }

    @Test("completed bars end at todo zero")
    func completedBarsEndAtTodoZero() {
        let geometry = GoalsTimelineGeometry(height: 200, maxDuration: 3_600)

        #expect(geometry.completedBarHeight(count: 4, maxOutcomeCount: 4) == geometry.zeroY)
    }

    @Test("failed bars start below todo zero")
    func failedBarsStartBelowTodoZero() {
        let geometry = GoalsTimelineGeometry(height: 200, maxDuration: 3_600)

        #expect(geometry.zeroY + geometry.failedBarHeight(count: 4, maxOutcomeCount: 4) == geometry.height)
    }
}
