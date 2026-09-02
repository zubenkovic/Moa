import Foundation

enum ActivityIndexEngine {
    /// Four independent raw inputs, deliberately never converted to a
    /// percent-of-target or averaged into one score: a percentage hides
    /// whether you're at 5,740 steps or 12,000, and an average hides
    /// which one actually needs attention — high steps and low strength
    /// work can look identical to balanced moderate effort once both are
    /// blended into abstract numbers. Each is shown next to its own
    /// target instead (`stepsTarget`, `minutesTarget`, `strengthTarget`),
    /// so exceeding it is just visible in the number itself. Sleep is
    /// average nightly duration rather than a computed 0–100 score, for
    /// the same reason the standalone Sleep Score was dropped from the
    /// Rest section — a score is one more layer of abstraction between
    /// the number and what it actually means. Its own recommended range
    /// and research citation live as a tooltip on RestSection's "Sleep"
    /// headline rather than as a target duplicated here.
    struct Result {
        let avgSteps: Double
        let weeklyMinutes: Double
        let weeklyStrengthMinutes: Double
        let avgSleepHours: Double
    }

    /// Daily average, per the weekend-warrior research this app leans
    /// on — weekly volume is what predicts benefit, not daily
    /// distribution.
    static let stepsTarget: Double = 7000
    /// Weekly moderate-or-more activity minutes.
    static let minutesTarget: Double = 150
    /// Weekly strength-training minutes — a single long session earning
    /// full credit is intentional, not an oversight; there's no
    /// per-session floor, only a weekly total.
    static let strengthTarget: Double = 60

    static func compute(sevenDayAvgSteps: Double, weeklyModerateMinutes: Double,
                         weeklyStrengthMinutes: Double, avgSleepHours: Double) -> Result {
        Result(
            avgSteps: sevenDayAvgSteps,
            weeklyMinutes: weeklyModerateMinutes,
            weeklyStrengthMinutes: weeklyStrengthMinutes,
            avgSleepHours: avgSleepHours
        )
    }
}
