import Foundation

enum MaxHeartRateEngine {
    enum Source { case observed, formula, manual }

    struct Result {
        let value: Double
        let source: Source
    }

    /// How far the observed 95th-percentile reading is allowed to drift
    /// from the age-formula prediction, in either direction, before it's
    /// judged not representative of true max HR. Tighter than the
    /// formula's own population variation (commonly cited around
    /// ±7-10bpm) would reject plenty of genuinely accurate readings just
    /// for differing from the population average; this sits close to
    /// that natural variation while still catching the two failure
    /// modes that actually matter: a sensor-glitch spike, or — far more
    /// common — a workout history that's never come close to a true
    /// max-effort push, which reads as implausibly *low* rather than
    /// high.
    private static let plausibleDriftBPM: Double = 10

    /// Resolves max heart rate from, in priority order: a manual value
    /// the person entered, the 95th percentile of their own
    /// workout-associated heart rate samples (sanity-checked against the
    /// age formula), or the formula alone.
    ///
    /// The sanity check matters: a naive "highest ever recorded" reading
    /// could come from a sensor glitch or something with nothing to do
    /// with fitness — or, just as easily, from a workout history that
    /// never actually pushed close to true max effort, which is the
    /// normal case for most regular training. Using the 95th percentile
    /// of samples already restricted to logged workouts, and falling
    /// back to the formula when the observed value drifts too far from
    /// the age prediction in *either* direction, avoids building zone
    /// math on a reading that doesn't represent real max effort. Real
    /// dangerous arrhythmias are Apple's own irregular rhythm
    /// notifications' job, not this calculation's.
    static func resolve(observedWorkoutSamples: [Double], age: Int?, manualOverride: Double?) -> Result {
        if let manualOverride {
            return Result(value: manualOverride, source: .manual)
        }

        // Tanaka formula — more accurate across a wider age range than
        // the classic 220-minus-age.
        let formulaValue = age.map { 206.9 - 0.67 * Double($0) }

        guard !observedWorkoutSamples.isEmpty else {
            return Result(value: formulaValue ?? 190, source: .formula)
        }

        let sorted = observedWorkoutSamples.sorted()
        let index = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        let observed95th = sorted[index]

        guard let formulaValue else {
            return Result(value: observed95th, source: .observed)
        }

        if abs(observed95th - formulaValue) > plausibleDriftBPM {
            return Result(value: formulaValue, source: .formula)
        }
        return Result(value: observed95th, source: .observed)
    }
}

/// A single manually-entered max heart rate, stored locally — mirrors
/// Apple's own automatic/manual toggle for workout zones.
enum ManualMaxHeartRateStore {
    private static let key = "manualMaxHeartRate"

    static var value: Double? {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            return stored > 0 ? stored : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
