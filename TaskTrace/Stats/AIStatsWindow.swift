import Foundation

nonisolated enum AIStatsWindow {
    static let rollingWindow: TimeInterval = 3 * 60 * 60
    static let bucketDuration: TimeInterval = 30
}
