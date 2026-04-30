//
//  Styles.swift
//  TaskTrace
//

import SwiftUI

enum Styles {
    enum Fonts {
        static let recordButtonIcon = Font.system(size: 36, weight: .semibold)
        static let analyticsFilterButton = Font.system(size: 17, weight: .semibold)
        static let analyticsMetricValue = Font.system(size: 36, weight: .bold, design: .rounded)
        static let sidebarIcon = Font.system(size: 19, weight: .semibold)
        static let sidebarLabel = Font.system(size: 18, weight: .semibold)
        static let sidebarSecondaryAction = Font.system(size: 16, weight: .semibold)
        static let calendarMonthLabel = Font.system(size: 18, weight: .semibold)
        static let calendarWeekdayLabel = Font.system(size: 15, weight: .medium)

        static let title3Semibold = Font.system(size: 22, weight: .semibold)
        static let headline = Font.system(size: 15, weight: .semibold)
        static let subheadline = Font.system(size: 14)
        static let subheadlineSemibold = Font.system(size: 14, weight: .semibold)
        static let footnote = Font.system(size: 13)
        static let footnoteSemibold = Font.system(size: 13, weight: .semibold)
        static let footnoteMonospaced = Font.system(size: 13, design: .monospaced)
        static let footnoteMonospacedDigit = Font.system(size: 13).monospacedDigit()
        static let caption = Font.system(size: 14)
        static let captionSemibold = Font.system(size: 14, weight: .semibold)
        static let caption2 = Font.system(size: 13)
        static let caption2Semibold = Font.system(size: 13, weight: .semibold)
        static let bodyMonospaced = Font.system(size: 15, design: .monospaced)

        static func calendarDay(isSelected: Bool) -> Font {
            Font.system(size: 16, weight: isSelected ? .semibold : .medium)
        }
    }
}
