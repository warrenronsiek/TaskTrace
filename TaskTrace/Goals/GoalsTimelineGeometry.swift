//
//  GoalsTimelineGeometry.swift
//  TaskTrace
//
//  Created by Codex on 5/13/26.
//

import CoreGraphics
import Foundation

nonisolated struct GoalsTimelineGeometry: Equatable {
    let height: CGFloat
    let maxDuration: Int

    var zeroY: CGFloat {
        height * 0.68
    }

    func timeY(duration: Int) -> CGFloat {
        let ratio = min(max(CGFloat(duration) / CGFloat(max(maxDuration, 1)), 0), 1)
        return zeroY - ratio * zeroY
    }

    func completedBarHeight(
        count: Int,
        maxOutcomeCount: Int
    ) -> CGFloat {
        CGFloat(count) / CGFloat(max(maxOutcomeCount, 1)) * zeroY
    }

    func failedBarHeight(
        count: Int,
        maxOutcomeCount: Int
    ) -> CGFloat {
        CGFloat(count) / CGFloat(max(maxOutcomeCount, 1)) * (height - zeroY)
    }
}
