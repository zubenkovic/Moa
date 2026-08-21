import SwiftUI
import HealthKit

struct ActivityIndexSection: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var weekResult: ActivityIndexEngine.Result?
    @State private var monthResult: ActivityIndexEngine.Result?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundStyle(.purple)
                Text("Activity Index").font(.title3.weight(.semibold))
                InfoTooltip(text: "Averages four things: daily average steps against 7,000/day, weekly moderate-or-more activity against 150 minutes, weekly strength-training minutes against 60, and nightly sleep scored the same way Apple's own Sleep Score is (duration, bedtime consistency, interruptions), averaged across the nights in the window. The first three are capped at 100% before averaging into the headline number, so one exceptional day can't skew it \u{2014} the number in brackets, when shown, is the same average without that cap, for whenever you've genuinely exceeded every target. Sleep has no “raw” version since it's already a 0–100 score rather than a ratio against a target — and because that score is deliberately hard to max out every night, 100% overall is realistically out of reach, same as it is for Apple's own score.")
                Spacer()
            }

            indexBlock(heading: "This week", result: weekResult)
            indexBlock(heading: "This month", result: monthResult)
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private func indexBlock(heading: String, result: ActivityIndexEngine.Result?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(.subheadline).foregroundStyle(.tertiary)

            if let result {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(result.overall)%")
                        .font(.title.weight(.medium))
                    if result.uncappedOverall > result.overall {
                        Text("(\(result.uncappedOverall)%)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    componentRow("Steps", result.stepsPercent, raw: result.stepsPercentRaw)
                    componentRow("Activity minutes", result.minutesPercent, raw: result.minutesPercentRaw)
                    componentRow("Strength minutes", result.strengthPercent, raw: result.strengthPercentRaw)
                    componentRow("Sleep", result.sleepPercent, raw: result.sleepPercent)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            } else {
                Text("Not enough history yet")
                    .font(.title.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func componentRow(_ label: String, _ percent: Int, raw: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(raw > percent ? "\(percent)% (\(raw)%)" : "\(percent)%")
        }
    }

    private func refresh() async {
        // `fetchDailyTotals` ends yesterday by design (see its doc
        // comment), so each window below asks for one day fewer and
        // appends today's own value — keeping the window's total width
        // the same (7 or 28 days) while shifting it to actually include
        // today, matching the strength minutes below, which already
        // include today on their own.
        async let weekStepsHistory = healthKit.fetchDailyTotals(for: .stepCount, unit: .count(), days: 6)
        async let weekExerciseHistory = healthKit.fetchDailyTotals(for: .appleExerciseTime, unit: .minute(), days: 6)
        async let weekStrengthMinutes = healthKit.fetchStrengthMinutes(days: 7)
        async let weekSleepNights = healthKit.fetchSleepNights(days: 7)

        async let monthStepsHistory = healthKit.fetchDailyTotals(for: .stepCount, unit: .count(), days: 27)
        async let monthExerciseHistory = healthKit.fetchDailyTotals(for: .appleExerciseTime, unit: .minute(), days: 27)
        async let monthStrengthMinutes = healthKit.fetchStrengthMinutes(days: 28)
        async let monthSleepNights = healthKit.fetchSleepNights(days: 28)

        async let todayStepsVal = healthKit.fetchTodayValue(for: .steps)
        async let todayExerciseVal = healthKit.fetchTodayValue(for: .exerciseMinutes)

        let todaySteps = await todayStepsVal ?? 0
        let todayExercise = await todayExerciseVal ?? 0

        weekResult = Self.compute(
            steps: (await weekStepsHistory) + [todaySteps], exerciseMinutes: (await weekExerciseHistory) + [todayExercise],
            strengthMinutes: await weekStrengthMinutes, sleepNights: await weekSleepNights, weeksInWindow: 1
        )
        monthResult = Self.compute(
            steps: (await monthStepsHistory) + [todaySteps], exerciseMinutes: (await monthExerciseHistory) + [todayExercise],
            strengthMinutes: await monthStrengthMinutes, sleepNights: await monthSleepNights, weeksInWindow: 4
        )
    }

    /// `weeksInWindow` converts a longer window's totals down to the
    /// weekly-equivalent rate the engine's benchmarks (150 min, 60
    /// strength minutes) are defined against, so the month view uses
    /// the same research-backed targets as the week view rather than a
    /// scaled-up monthly one.
    private static func compute(steps: [Double], exerciseMinutes: [Double], strengthMinutes: Double,
                                 sleepNights: [HealthKitManager.SleepNightSummary], weeksInWindow: Double) -> ActivityIndexEngine.Result? {
        guard !steps.isEmpty, !sleepNights.isEmpty else { return nil }

        let avgSteps = steps.reduce(0, +) / Double(steps.count)
        let weeklyMinutes = exerciseMinutes.reduce(0, +) / weeksInWindow
        let weeklyStrengthMinutes = strengthMinutes / weeksInWindow

        return ActivityIndexEngine.compute(
            sevenDayAvgSteps: avgSteps,
            weeklyModerateMinutes: weeklyMinutes,
            weeklyStrengthMinutes: weeklyStrengthMinutes,
            sleepScoreAvg: averageSleepScore(nights: sleepNights)
        )
    }

    /// Apple-style nightly sleep score (see SleepScoreEngine), one per
    /// night, averaged across the window — bedtime consistency is
    /// judged against the window's own median bedtime, same approach
    /// RestSection uses for last night alone. A night with no bedtime
    /// data falls back to zero variance (full consistency credit)
    /// rather than penalizing a gap in the data.
    private static func averageSleepScore(nights: [HealthKitManager.SleepNightSummary],
                                           calendar: Calendar = .current) -> Double {
        let median = SleepRegularity.summarize(times: nights.compactMap(\.bedStart), calendar: calendar)?.median

        let scores = nights.map { night -> Double in
            let varianceMinutes: Double
            if let median, let bedStart = night.bedStart {
                varianceMinutes = SleepRegularity.minutesApart(median, bedStart, calendar: calendar)
            } else {
                varianceMinutes = 0
            }
            return Double(SleepScoreEngine.score(
                asleepHours: night.asleepHours,
                bedtimeVarianceMinutes: varianceMinutes,
                interruptionMinutes: night.interruptionMinutes
            ))
        }
        return scores.reduce(0, +) / Double(scores.count)
    }
}
