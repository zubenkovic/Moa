import Foundation
import Combine

enum RMREngine {
    /// More accurate than Apple's population-average formula for anyone
    /// whose muscle mass doesn't match the "average person" that
    /// formula assumes — but only as reliable as the lean-mass number
    /// feeding it, which for most people comes from a consumer smart
    /// scale's bioelectrical-impedance estimate, not a lab measurement.
    static func katchMcArdle(leanBodyMassKg: Double) -> Double {
        370 + 21.6 * leanBodyMassKg
    }

    /// Median rather than mean for Apple's resting-energy figure — with
    /// only 7 days of data, a single low-coverage day (Watch charging,
    /// not worn overnight) drags a plain average down hard, while a
    /// median simply ignores how extreme that one day was rather than
    /// needing an arbitrary threshold to detect and exclude it.
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}

enum RestingEnergyMethod: String {
    case appleEstimate
    case katchMcArdle
}

/// Which resting-energy estimate counts as authoritative — highlighted
/// in the Resting energy section, and the one fed into Movement's Total
/// calories figure. Defaults to Apple's estimate since it's always
/// available; Katch-McArdle needs lean-mass data from a smart scale.
///
/// An `ObservableObject` rather than a plain `UserDefaults` wrapper
/// because it's read by two independent sections (Resting energy and
/// Movement) that each fetch and compute on their own — without
/// publishing changes, Movement would only see a new preference the
/// next time its own `.task` ran, i.e. after a fresh app launch.
@MainActor
final class RestingEnergyPreferenceStore: ObservableObject {
    static let shared = RestingEnergyPreferenceStore()

    private static let key = "restingEnergyMethod"

    @Published var value: RestingEnergyMethod {
        didSet {
            UserDefaults.standard.set(value.rawValue, forKey: Self.key)
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let method = RestingEnergyMethod(rawValue: raw) {
            value = method
        } else {
            value = .appleEstimate
        }
    }
}
