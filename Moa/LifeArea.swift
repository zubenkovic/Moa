import SwiftUI

/// The three life areas this app presents, each backed entirely by
/// passive or wearable HealthKit data — no manual logging. Nutrition and
/// a standalone "Mind" tile were both deliberately cut: nutrition needs
/// its own logging UI that's out of scope, and daily self-rated health
/// (see HealthRatingStore) replaced Mind as a home-screen element rather
/// than a fourth tile, since it's evidence-backed rather than a bespoke
/// mood log with no payoff.
enum LifeArea: String, CaseIterable, Identifiable, Hashable {
    case movement
    case sleep
    case heart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movement: return "Movement"
        case .sleep:    return "Rest"
        case .heart:    return "Heart & Vitals"
        }
    }

    var subtitle: String {
        switch self {
        case .movement: return "How much you moved today"
        case .sleep:    return "How rested you are"
        case .heart:    return "What your heart is telling you"
        }
    }

    var systemImage: String {
        switch self {
        case .movement: return "figure.walk"
        case .sleep:    return "moon.zzz.fill"
        case .heart:    return "heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .movement: return .green
        case .sleep:    return .indigo
        case .heart:    return .red
        }
    }

    /// The one number shown on the home screen. Kept as data rather than
    /// hardcoded in a view — the cheap first step toward the "customizable
    /// home screen" you want later. A future settings screen just needs
    /// to write a chosen `MetricKind` per area instead of always reading
    /// this default.
    var headlineMetric: MetricKind {
        switch self {
        case .movement: return .steps
        case .sleep:    return .sleepHours
        case .heart:    return .restingHeartRate
        }
    }

    /// Everything else, one tap deeper.
    var detailMetrics: [MetricKind] {
        switch self {
        case .movement: return [.distance, .exerciseMinutes, .standMinutes, .activeCalories]
        case .sleep:    return [.sleepEfficiency]
        case .heart:    return [.heartRateVariability]
        }
    }
}

/// How much real data we have for a given life area right now. Every
/// screen checks this before deciding what to render, instead of
/// assuming a wearable is present.
enum DataRichness {
    case none        // nothing yet
    case manual      // only what the person has logged themselves
    case passive     // phone-only automatic data (e.g. step count)
    case continuous  // wearable-driven data (e.g. resting heart rate)

    var explanation: String {
        switch self {
        case .none:       return "No data yet."
        case .manual:     return "Based on what you've logged yourself."
        case .passive:    return "Measured automatically by your iPhone."
        case .continuous: return "Measured by your wearable."
        }
    }
}

/// A ready-to-render snapshot of one life area's home-screen row.
struct LifeAreaSummary: Identifiable {
    let id = UUID()
    let area: LifeArea
    var richness: DataRichness
    var headline: String
    var supportingText: String
}
