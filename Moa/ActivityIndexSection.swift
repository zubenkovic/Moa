import SwiftUI
import HealthKit

struct ActivityIndexSection: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @State private var weekResult: ActivityIndexEngine.Result?
    @State private var monthResult: ActivityIndexEngine.Result?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundStyle(.teal)
                HStack(spacing: 2) {
                    Text("Activity Index").font(.title3.weight(.semibold))
                    InfoTooltip(text: "Four independent numbers, each shown against its own target rather than converted to a percentage \u{2014} a percentage would hide whether you're at 5,740 steps or 12,000. Steps is daily average against 7,000, cardio is weekly moderate-or-more minutes against 150, strength is weekly strength minutes against 60, sleep is average nightly duration against the 7\u{2013}9 hour range recommended for adults. None are capped \u{2014} exceeding a target just shows as the real number.")
                }
                Spacer()
            }

            indexBlock(heading: "This week", result: weekResult)
            Divider()
            indexBlock(heading: "This month", result: monthResult)
        }
        .task { await refresh() }
    }

    /// A simple list rather than a 2-column grid — the values here
    /// ("5,740/7,000 steps") run longer than most other stat cells in
    /// the app, and a half-width column is exactly where that wraps or
    /// crowds on a small phone.
    @ViewBuilder
    private func indexBlock(heading: String, result: ActivityIndexEngine.Result?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).sectionHeadingStyle()

            if let result {
                VStack(alignment: .leading, spacing: 10) {
                    componentRow("Steps (avg/day)", value: "\(NumberFormat.int(result.avgSteps))/\(NumberFormat.int(ActivityIndexEngine.stepsTarget)) steps")
                    componentRow("Cardio minutes (avg/week)", value: "\(NumberFormat.int(result.weeklyMinutes))/\(NumberFormat.int(ActivityIndexEngine.minutesTarget)) min")
                    componentRow("Strength minutes (avg/week)", value: "\(NumberFormat.int(result.weeklyStrengthMinutes))/\(NumberFormat.int(ActivityIndexEngine.strengthTarget)) min")
                    // The 7\u{2013}9 hour recommendation and its research
                    // citation now live once, as a tooltip on the "Sleep"
                    // headline in RestSection, rather than repeated here
                    // as plain-text copy next to a number with no room to
                    // explain where it comes from.
                    componentRow("Sleep (avg/night)", value: "\(NumberFormat.decimal1(result.avgSleepHours)) hrs")
                }
            } else {
                Text("Not enough history yet")
                    .headlineValueStyle()
            }
        }
    }

    /// Label on the left, raw value against its own target on the
    /// right — no percentage, no capping, exceeding a target is just
    /// visible in the number itself.
    private func componentRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).statLabelStyle()
            Spacer()
            Text(value).statValueStyle()
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

        SectionLoadCoordinator.shared.markLoaded("Activity Index")
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
        let avgSleepHours = sleepNights.map(\.asleepHours).reduce(0, +) / Double(sleepNights.count)

        return ActivityIndexEngine.compute(
            sevenDayAvgSteps: avgSteps,
            weeklyModerateMinutes: weeklyMinutes,
            weeklyStrengthMinutes: weeklyStrengthMinutes,
            avgSleepHours: avgSleepHours
        )
    }
}
