import Foundation

enum ActivityIndexEngine {
    struct Result {
        let overall: Int
        /// The same average without capping each component at 100%
        /// first — how far past target you actually are, on days
        /// where you've exceeded it. Only meaningfully different from
        /// `overall` when it's greater; sleep can never push it up,
        /// since it's already a 0–100 score rather than a ratio
        /// against a target that can be exceeded.
        let uncappedOverall: Int
        let stepsPercent: Int
        let minutesPercent: Int
        let strengthPercent: Int
        let sleepPercent: Int
        /// Uncapped counterparts to the three "more is better" percents
        /// above, for showing genuine overperformance per-component the
        /// same way `uncappedOverall` does for the headline. No raw
        /// sleep value — it can't exceed 100% in the first place.
        let stepsPercentRaw: Int
        let minutesPercentRaw: Int
        let strengthPercentRaw: Int
    }

    /// Four components. Steps, minutes, and strength are each capped at
    /// 100% before averaging into `overall`, so one exceptional day
    /// can't skew the headline picture — `uncappedOverall` keeps the
    /// same average without that cap, for showing genuine
    /// overperformance alongside the stable headline. Steps and
    /// minutes/strength are expressed in the unit their own research
    /// actually uses — steps as a daily average, minutes and strength
    /// minutes as weekly totals, since the weekend-warrior research
    /// this app leans on shows weekly volume is what predicts benefit,
    /// not daily distribution or session count (a single long strength
    /// session earning full credit is intentional, not an oversight).
    /// Passing a longer window's totals divided down to a
    /// weekly-equivalent rate (see ActivityIndexSection's monthly call)
    /// reuses the same weekly benchmarks unchanged.
    ///
    /// `sleepScoreAvg` is different in kind from the other three: it's
    /// the average of Apple-style nightly sleep scores (see
    /// SleepScoreEngine) rather than a ratio against a single target,
    /// so there's nothing to cap or express "raw" — a 0–100 score is
    /// already its own ceiling, and by design that ceiling is rarely
    /// actually reached even on a great week (perfect duration,
    /// consistency, and interruptions, every single night). That means
    /// `overall` itself will realistically fall short of a clean 100%
    /// too, same as Apple's own sleep score does — accepted as correct
    /// rather than something to compensate for.
    static func compute(sevenDayAvgSteps: Double, weeklyModerateMinutes: Double,
                         weeklyStrengthMinutes: Double, sleepScoreAvg: Double) -> Result {
        let stepsPctRaw = (sevenDayAvgSteps / 7000) * 100
        let minutesPctRaw = (weeklyModerateMinutes / 150) * 100
        let strengthPctRaw = (weeklyStrengthMinutes / 60) * 100
        let sleepPct = min(100, max(0, sleepScoreAvg))

        let stepsPct = min(100, stepsPctRaw)
        let minutesPct = min(100, minutesPctRaw)
        let strengthPct = min(100, strengthPctRaw)

        let overall = (stepsPct + minutesPct + strengthPct + sleepPct) / 4
        let uncappedOverall = (stepsPctRaw + minutesPctRaw + strengthPctRaw + sleepPct) / 4

        return Result(
            overall: Int(overall.rounded()),
            uncappedOverall: Int(uncappedOverall.rounded()),
            stepsPercent: Int(stepsPct.rounded()),
            minutesPercent: Int(minutesPct.rounded()),
            strengthPercent: Int(strengthPct.rounded()),
            sleepPercent: Int(sleepPct.rounded()),
            stepsPercentRaw: Int(stepsPctRaw.rounded()),
            minutesPercentRaw: Int(minutesPctRaw.rounded()),
            strengthPercentRaw: Int(strengthPctRaw.rounded())
        )
    }
}
