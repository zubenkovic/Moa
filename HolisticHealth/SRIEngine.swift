import Foundation

/// Sleep Regularity Index (Phillips et al., 2017) — how similar your
/// sleep/wake schedule is from one day to the next, on a native
/// -100 (perfectly out of phase) to +100 (identical schedule) scale.
/// Kept on that native scale rather than renormalized to 0-100 the way
/// the app's own Sleep Score is, since SRI is an independent,
/// already-validated published metric — remapping it would misrepresent
/// what the number actually is.
///
/// Deliberately has zero HealthKit imports, matching BaselineEngine —
/// pure logic over epoch arrays, easy to unit test and reason about
/// independent of how the data was fetched. Callers pass raw category
/// sample tuples; `isAsleepValue` hardcodes the same raw values
/// `HKCategoryValueSleepAnalysis` uses (0 = inBed, 2 = awake, everything
/// else 1/3/4/5 = an asleep stage) rather than importing HealthKit just
/// for those constants.
enum SRIEngine {
    static let epochsPerDay = 1440

    /// One 1,440-entry asleep/awake profile per requested calendar day
    /// (midnight to midnight, local time) — true where any asleep-stage
    /// sample (unspecified/core/deep/REM) covers that minute. `.inBed`
    /// alone does not count as asleep, matching the definition already
    /// established elsewhere in the app (see HealthKitManager's own
    /// sleep-night fetching) for exactly the same reason: counting
    /// in-bed-but-awake time as asleep would both overstate sleep and
    /// hide real awakenings.
    static func dailyEpochProfiles(
        samples: [(start: Date, end: Date, value: Int)],
        days: [Date],
        calendar: Calendar = .current
    ) -> [Date: [Bool]] {
        var profiles: [Date: [Bool]] = [:]
        for day in days {
            let dayStart = calendar.startOfDay(for: day)
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { continue }

            var epochs = [Bool](repeating: false, count: epochsPerDay)
            for sample in samples {
                guard isAsleepValue(sample.value) else { continue }
                let clippedStart = max(sample.start, dayStart)
                let clippedEnd = min(sample.end, dayEnd)
                guard clippedStart < clippedEnd else { continue }

                let startMinute = max(0, Int(clippedStart.timeIntervalSince(dayStart) / 60))
                let endMinute = min(epochsPerDay, Int(ceil(clippedEnd.timeIntervalSince(dayStart) / 60)))
                guard startMinute < endMinute else { continue }
                for minute in startMinute..<endMinute {
                    epochs[minute] = true
                }
            }
            profiles[dayStart] = epochs
        }
        return profiles
    }

    /// Raw `HKCategoryValueSleepAnalysis` values: 0 = inBed, 1 =
    /// asleepUnspecified, 2 = awake, 3 = asleepCore, 4 = asleepDeep,
    /// 5 = asleepREM. Anything not inBed or awake is an asleep stage.
    static func isAsleepValue(_ value: Int) -> Bool {
        value != 0 && value != 2
    }

    /// Same-clock-minute label agreement between two consecutive days'
    /// profiles, scaled to Phillips et al.'s -100...+100 range. Both
    /// arrays must be `epochsPerDay` long.
    static func pairwiseSRI(_ dayA: [Bool], _ dayB: [Bool]) -> Double {
        let matching = zip(dayA, dayB).lazy.filter { $0 == $1 }.count
        return -100 + (200.0 / Double(epochsPerDay)) * Double(matching)
    }

    struct WindowResult {
        let value: Double
        let nightsUsed: Int
    }

    /// Averages pairwise SRI across consecutive calendar days in
    /// `orderedDays` (oldest to newest, no gaps expected). A day with
    /// zero recorded sleep data (an all-false profile — nothing came
    /// back from HealthKit that day, not just a short night) is
    /// excluded from any pair it would be part of, rather than counted
    /// as a full mismatch, so one missing night doesn't unfairly tank
    /// the score. Returns nil if fewer than one valid pair exists.
    static func windowSRI(profiles: [Date: [Bool]], orderedDays: [Date]) -> WindowResult? {
        guard orderedDays.count >= 2 else { return nil }

        var pairwiseScores: [Double] = []
        var nightsUsed = Set<Date>()
        for i in 1..<orderedDays.count {
            let previousDay = orderedDays[i - 1]
            let currentDay = orderedDays[i]
            guard let previousProfile = profiles[previousDay], let currentProfile = profiles[currentDay],
                  previousProfile.contains(true), currentProfile.contains(true) else { continue }

            pairwiseScores.append(pairwiseSRI(previousProfile, currentProfile))
            nightsUsed.insert(previousDay)
            nightsUsed.insert(currentDay)
        }

        guard !pairwiseScores.isEmpty else { return nil }
        let average = pairwiseScores.reduce(0, +) / Double(pairwiseScores.count)
        return WindowResult(value: average, nightsUsed: nightsUsed.count)
    }

    /// A trailing history of window-level SRI values — e.g. the 7-day
    /// SRI as it stood at the end of each of the last several days —
    /// for comparing the current window's regularity against the
    /// person's own personal norm, the same "compare to your own
    /// rolling baseline" principle used throughout the app. Each point
    /// needs its own full `windowLength`-day lookback, so this only
    /// produces as many points as the available day range allows.
    static func slidingWindowHistory(
        profiles: [Date: [Bool]], allDaysOldestToNewest: [Date], windowLength: Int
    ) -> [Double] {
        guard allDaysOldestToNewest.count >= windowLength else { return [] }

        var values: [Double] = []
        for endIndex in (windowLength - 1)..<allDaysOldestToNewest.count {
            let windowDays = Array(allDaysOldestToNewest[(endIndex - windowLength + 1)...endIndex])
            if let result = windowSRI(profiles: profiles, orderedDays: windowDays) {
                values.append(result.value)
            }
        }
        return values
    }
}
