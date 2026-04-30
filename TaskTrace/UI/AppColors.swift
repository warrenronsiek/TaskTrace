//
//  AppColors.swift
//  TaskTrace
//
//  Created by Codex on 3/13/26.
//

import AppKit
import SwiftUI

enum AppColors {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textOnAccent = Color.white

    static let recordIdle = dynamic(
        light: .controlAccentColor,
        dark: NSColor(srgbRed: 0.47, green: 0.78, blue: 0.96, alpha: 1)
    )
    static let recordActive = dynamic(
        light: .systemRed,
        dark: NSColor(srgbRed: 0.98, green: 0.64, blue: 0.72, alpha: 1)
    )

    static let success = dynamic(
        light: .systemGreen,
        dark: NSColor(srgbRed: 0.60, green: 0.92, blue: 0.78, alpha: 1)
    )
    static let danger = dynamic(
        light: .systemRed,
        dark: NSColor(srgbRed: 0.98, green: 0.66, blue: 0.73, alpha: 1)
    )

    static let errorBackground = dynamic(
        light: NSColor.systemRed.withAlphaComponent(0.10),
        dark: NSColor(srgbRed: 0.98, green: 0.66, blue: 0.73, alpha: 0.18)
    )
    static let cardBackground = dynamic(
        light: NSColor.secondaryLabelColor.withAlphaComponent(0.12),
        dark: NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 0.92)
    )
    static let insetBackground = dynamic(
        light: NSColor.secondaryLabelColor.withAlphaComponent(0.08),
        dark: NSColor(srgbRed: 0.19, green: 0.22, blue: 0.29, alpha: 0.9)
    )
    static let chipBackground = dynamic(
        light: NSColor.secondaryLabelColor.withAlphaComponent(0.14),
        dark: NSColor(srgbRed: 0.23, green: 0.27, blue: 0.36, alpha: 0.95)
    )
    static let timelineGrid = dynamic(
        light: NSColor.secondaryLabelColor.withAlphaComponent(0.15),
        dark: NSColor.white.withAlphaComponent(0.08)
    )
    static let timelineOverlayText = dynamic(
        light: NSColor.black.withAlphaComponent(0.70),
        dark: NSColor.black.withAlphaComponent(0.78)
    )
    static let timelineDetailText = dynamic(
        light: NSColor.black.withAlphaComponent(0.84),
        dark: NSColor.black.withAlphaComponent(0.90)
    )
    static let timelineDetailSecondaryText = dynamic(
        light: NSColor.black.withAlphaComponent(0.64),
        dark: NSColor.black.withAlphaComponent(0.72)
    )
    static let timelineDetailChrome = dynamic(
        light: NSColor.black.withAlphaComponent(0.08),
        dark: NSColor.black.withAlphaComponent(0.14)
    )
    static let timelineUnassigned = dynamic(
        light: NSColor.secondaryLabelColor.withAlphaComponent(0.22),
        dark: NSColor(srgbRed: 0.30, green: 0.34, blue: 0.43, alpha: 0.92)
    )

    static let accent = dynamic(
        light: NSColor(srgbRed: 0.30, green: 0.58, blue: 0.88, alpha: 1),
        dark: NSColor(srgbRed: 0.50, green: 0.76, blue: 0.94, alpha: 1)
    )

    static let calendarSelection = dynamic(
        light: .controlAccentColor,
        dark: NSColor(srgbRed: 0.52, green: 0.80, blue: 0.98, alpha: 1)
    )

    static func analyticsTagColor(for tag: String) -> Color {
        let normalizedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedTag == "all" {
            return dynamic(
                light: NSColor(srgbRed: 0.13, green: 0.47, blue: 0.85, alpha: 1),
                dark: NSColor(srgbRed: 0.46, green: 0.75, blue: 0.98, alpha: 1)
            )
        }

        if normalizedTag == AnalyticsStore.untaggedName.lowercased() {
            return dynamic(
                light: NSColor(srgbRed: 0.64, green: 0.65, blue: 0.71, alpha: 1),
                dark: NSColor(srgbRed: 0.78, green: 0.78, blue: 0.86, alpha: 1)
            )
        }

        if normalizedTag == SystemTags.inactiveName {
            return dynamic(
                light: NSColor(srgbRed: 0.77, green: 0.49, blue: 0.14, alpha: 1),
                dark: NSColor(srgbRed: 0.95, green: 0.72, blue: 0.36, alpha: 1)
            )
        }

        if normalizedTag == SystemTags.taggingFailureName {
            return dynamic(
                light: NSColor(srgbRed: 0.79, green: 0.18, blue: 0.49, alpha: 1),
                dark: NSColor(srgbRed: 0.98, green: 0.47, blue: 0.73, alpha: 1)
            )
        }

        let lightPalette: [NSColor] = [
            NSColor(srgbRed: 0.12, green: 0.45, blue: 0.86, alpha: 1),
            NSColor(srgbRed: 0.84, green: 0.22, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 0.16, green: 0.62, blue: 0.28, alpha: 1),
            NSColor(srgbRed: 0.88, green: 0.50, blue: 0.09, alpha: 1),
            NSColor(srgbRed: 0.42, green: 0.27, blue: 0.84, alpha: 1),
            NSColor(srgbRed: 0.02, green: 0.64, blue: 0.63, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.14, blue: 0.61, alpha: 1),
            NSColor(srgbRed: 0.47, green: 0.60, blue: 0.05, alpha: 1),
            NSColor(srgbRed: 0.70, green: 0.22, blue: 0.13, alpha: 1),
            NSColor(srgbRed: 0.00, green: 0.56, blue: 0.78, alpha: 1),
            NSColor(srgbRed: 0.57, green: 0.29, blue: 0.62, alpha: 1),
            NSColor(srgbRed: 0.73, green: 0.53, blue: 0.03, alpha: 1)
        ]
        let darkPalette: [NSColor] = [
            NSColor(srgbRed: 0.46, green: 0.74, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.49, blue: 0.50, alpha: 1),
            NSColor(srgbRed: 0.50, green: 0.92, blue: 0.56, alpha: 1),
            NSColor(srgbRed: 0.99, green: 0.72, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 0.71, green: 0.61, blue: 0.99, alpha: 1),
            NSColor(srgbRed: 0.39, green: 0.92, blue: 0.90, alpha: 1),
            NSColor(srgbRed: 0.98, green: 0.52, blue: 0.80, alpha: 1),
            NSColor(srgbRed: 0.76, green: 0.88, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 0.94, green: 0.55, blue: 0.41, alpha: 1),
            NSColor(srgbRed: 0.45, green: 0.84, blue: 0.97, alpha: 1),
            NSColor(srgbRed: 0.82, green: 0.60, blue: 0.92, alpha: 1),
            NSColor(srgbRed: 0.93, green: 0.78, blue: 0.33, alpha: 1)
        ]
        let hash = normalizedTag.utf8.reduce(into: UInt64(14_695_981_039_346_656_037)) { partialResult, byte in
            partialResult ^= UInt64(byte)
            partialResult &*= 1_099_511_628_211
        }
        let index = Int(hash % UInt64(lightPalette.count))

        return dynamic(light: lightPalette[index], dark: darkPalette[index])
    }

    static func timelineColor(for overviewID: Int64?) -> Color {
        guard let overviewID else {
            return timelineUnassigned
        }

        let lightPalette: [NSColor] = [
            NSColor(srgbRed: 0.88, green: 0.80, blue: 0.79, alpha: 1),
            NSColor(srgbRed: 0.77, green: 0.86, blue: 0.80, alpha: 1),
            NSColor(srgbRed: 0.78, green: 0.84, blue: 0.91, alpha: 1),
            NSColor(srgbRed: 0.95, green: 0.88, blue: 0.74, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.80, blue: 0.91, alpha: 1)
        ]
        let darkPalette: [NSColor] = [
            NSColor(srgbRed: 0.54, green: 0.82, blue: 0.97, alpha: 0.94),
            NSColor(srgbRed: 0.61, green: 0.92, blue: 0.79, alpha: 0.94),
            NSColor(srgbRed: 0.98, green: 0.75, blue: 0.67, alpha: 0.94),
            NSColor(srgbRed: 0.80, green: 0.72, blue: 0.98, alpha: 0.94),
            NSColor(srgbRed: 0.97, green: 0.88, blue: 0.60, alpha: 0.94)
        ]
        let index = Int(overviewID % Int64(lightPalette.count))

        return dynamic(light: lightPalette[index], dark: darkPalette[index])
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
