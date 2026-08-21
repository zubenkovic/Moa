import Foundation

/// Computes a sleep score using the same weighting Apple validated for
/// its own watchOS 26 Sleep Score — duration 50%, bedtime consistency
/// 30%, interruptions 20% — against more than five million nights of
/// data through the Apple Heart and Movement Study. Apple's actual
/// computed score isn't exposed via HealthKit, so this is our own
/// version of the same validated formula, built entirely from data
/// already fetched for the Rest section, and fully transparent about
/// how it's calculated (see the tooltip in RestSection).
enum SleepScoreEngine {

    static func score(asleepHours: Double, bedtimeVarianceMinutes: Double, interruptionMinutes: Double) -> Int {
        let durationScore = durationComponent(asleepHours) * 50
        let consistencyScore = consistencyComponent(bedtimeVarianceMinutes) * 30
        let interruptionScore = interruptionComponent(interruptionMinutes) * 20
        return Int((durationScore + consistencyScore + interruptionScore).rounded())
    }

    /// Full credit across the recommended 7–9 hour range, tapering to
    /// zero at 4 hours below and 12 hours above — duration is U-shaped,
    /// same reasoning as the Activity Index's sleep component: too much
    /// sleep carries its own risk in the research, just as too little
    /// does. This sub-score feeds both the standalone Sleep Score
    /// display (RestSection) and the Activity Index's sleep component
    /// (ActivityIndexSection) — touching this shape moves both.
    private static func durationComponent(_ hours: Double) -> Double {
        if hours >= 7 && hours <= 9 { return 1 }
        if hours < 7 { return max(0, 1 - (7 - hours) / 3) }
        return max(0, 1 - (hours - 9) / 3)
    }

    /// Full credit for a bedtime within 30 minutes of your own recent
    /// median; tapers to zero by 2 hours off. Tunable starting point,
    /// not a scientific constant.
    private static func consistencyComponent(_ varianceMinutes: Double) -> Double {
        max(0, 1 - max(0, varianceMinutes - 30) / 90)
    }

    /// Full credit for under 15 minutes awake overnight; tapers to zero
    /// by 75 minutes.
    private static func interruptionComponent(_ minutes: Double) -> Double {
        max(0, 1 - max(0, minutes - 15) / 60)
    }
}
