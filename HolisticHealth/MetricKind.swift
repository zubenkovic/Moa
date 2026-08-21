import Foundation

/// Every individual value the app knows how to fetch and show. Kept
/// separate from `LifeArea` on purpose: an area just points at whichever
/// metrics are relevant to it (see `headlineMetric` / `detailMetrics`),
/// so adding a new number later — or letting someone choose their own
/// headline metric — never means touching the fetching or formatting code.
enum MetricKind: String, CaseIterable, Hashable {
    case steps
    case distance
    case exerciseMinutes
    case standMinutes
    case activeCalories
    case sleepHours
    case sleepEfficiency
    case restingHeartRate
    case heartRateVariability
    case vo2Max
    case walkingHeartRateAverage
    case heartRateRecovery

    var label: String {
        switch self {
        case .steps:                  return "Steps"
        case .distance:                return "Distance"
        case .exerciseMinutes:         return "Exercise"
        case .standMinutes:            return "Stand time"
        case .activeCalories:          return "Active energy"
        case .sleepHours:              return "Time asleep"
        case .sleepEfficiency:         return "Sleep efficiency"
        case .restingHeartRate:        return "Resting heart rate"
        case .heartRateVariability:    return "HRV"
        case .vo2Max:                  return "VO2 max"
        case .walkingHeartRateAverage: return "Walking heart rate"
        case .heartRateRecovery:       return "Heart rate recovery"
        }
    }

    /// Deliberately no calorie *targets*, no distance/pace judgment, no
    /// color-coded good/bad ranges here — every value is shown plainly
    /// and only ever compared against the person's own baseline elsewhere.
    static func format(_ value: Double, for kind: MetricKind) -> String {
        switch kind {
        case .steps:               return "\(Int(value)) steps"
        case .distance:             return String(format: "%.1f km", value / 1000)
        case .exerciseMinutes:      return "\(Int(value)) min"
        case .standMinutes:         return "\(Int(value)) min"
        case .activeCalories:       return "\(Int(value)) kcal"
        case .sleepHours:           return String(format: "%.1f hrs", value)
        case .sleepEfficiency:      return "\(Int(value))%"
        case .restingHeartRate:        return "\(Int(value)) bpm"
        case .heartRateVariability:    return "\(Int(value)) ms"
        case .vo2Max:                  return String(format: "%.1f mL/kg/min", value)
        case .walkingHeartRateAverage: return "\(Int(value)) bpm"
        case .heartRateRecovery:       return "\(Int(value)) bpm drop"
        }
    }
}
