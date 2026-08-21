import SwiftUI
import HealthKit

struct MovementSection: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var restingEnergyPreference = RestingEnergyPreferenceStore.shared

    @State private var steps: Double?
    @State private var distance: Double?
    @State private var exerciseMinutes: Double?
    @State private var standMinutes: Double?
    @State private var activeCalories: Double?
    @State private var neat: Double?
    @State private var appleRestingEstimate: Double?
    @State private var katchToday: Double?
    @State private var activeCaloriesHistoryRaw: [Double] = []
    @State private var basalHistoryRaw: [Double] = []
    @State private var stepsRange: (low: Double, high: Double)?
    @State private var distanceRange: (low: Double, high: Double)?
    @State private var exerciseRange: (low: Double, high: Double)?
    @State private var standRange: (low: Double, high: Double)?
    @State private var activeCaloriesRange: (low: Double, high: Double)?
    @State private var neatRange: (low: Double, high: Double)?
    @State private var vigorousMomentsRange: (low: Double, high: Double)?
    @State private var activeDaysWeek: [Bool] = Array(repeating: false, count: 7)
    @State private var activeDaysMonth: [Bool] = Array(repeating: false, count: 28)
    @State private var strengthDaysWeek: [Bool] = Array(repeating: false, count: 7)
    @State private var strengthDaysMonth: [Bool] = Array(repeating: false, count: 28)
    @State private var todaysWorkouts: [HealthKitManager.WorkoutSummary] = []
    @State private var vigorousMoments: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: LifeArea.movement.systemImage)
                    .foregroundStyle(LifeArea.movement.tint)
                Text("Movement").font(.title3.weight(.semibold))
                Spacer()
                Text("Today").font(.subheadline).foregroundStyle(.tertiary)
            }

            Text(steps.map { "\(Int($0)) steps" } ?? "No data yet")
                .font(.title.weight(.medium))

            if let steps, let range = stepsRange {
                LowHighIndicator(value: steps, low: range.low, high: range.high)
            }

            Text("\(Int(steps ?? 0)) / 7,000")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            statGrid

            if !todaysWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's workouts").font(.subheadline).foregroundStyle(.tertiary)
                    ForEach(todaysWorkouts) { workout in
                        HStack {
                            Text(workout.typeName)
                            Spacer()
                            Text("\(Int(workout.duration / 60)) min")
                            if let cal = workout.totalEnergyBurned {
                                Text("\u{00B7} \(Int(cal)) kcal")
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("This week workouts").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    WeeklyDotStrip(activeDays: activeDaysWeek)
                    Text("Active days \(activeDaysWeek.filter { $0 }.count)/7")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    WeeklyDotStrip(activeDays: strengthDaysWeek)
                    Text("Strength days \(strengthDaysWeek.filter { $0 }.count)/7")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("This month workouts").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    MonthlyDotGrid(activeDays: activeDaysMonth)
                    Text("Active days \(activeDaysMonth.filter { $0 }.count)/28")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    MonthlyDotGrid(activeDays: strengthDaysMonth)
                    Text("Strength days \(strengthDaysMonth.filter { $0 }.count)/28")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .task { await refresh() }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
            if let distance {
                statCell("Distance", String(format: "%.1f km", distance / 1000), value: distance, range: distanceRange)
            }
            if let exerciseMinutes {
                statCell("Exercise", "\(Int(exerciseMinutes)) min", value: exerciseMinutes, range: exerciseRange)
            }
            if let standMinutes {
                statCell("Stood", "\(Int(standMinutes)) min", value: standMinutes, range: standRange)
            }
            if let activeCalories {
                statCell("Active energy", "\(Int(activeCalories)) kcal", value: activeCalories, range: activeCaloriesRange)
            }
            if let neat {
                statCell("Non-exercise", "~\(Int(neat)) kcal", value: neat, range: neatRange)
            }
            if let totalCalories {
                statCell(
                    "Total calories", "\(Int(totalCalories)) kcal", value: totalCalories, range: totalCaloriesRange,
                    tooltip: "Active energy plus your resting energy estimate (whichever one is selected in Resting energy \u{2014} tap either number there to switch)."
                )
            }
            if let vigorousMoments {
                statCell(
                    "Vigorous moments",
                    "\(vigorousMoments)",
                    value: Double(vigorousMoments),
                    range: vigorousMomentsRange,
                    tooltip: vigorousMomentsTooltip
                )
            } else {
                unavailableStatCell("Vigorous moments", tooltip: vigorousMomentsTooltip)
            }
        }
    }

    /// Same label/tooltip treatment as a normal stat cell, but for when
    /// there's nothing to plot — no bar, no invented number. Keeping
    /// this visible (rather than hiding the whole stat) matters even for
    /// phone-only users with no wearable: the tooltip is the only place
    /// they'd learn the feature exists and why it isn't showing a value.
    private func unavailableStatCell(_ label: String, tooltip: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.subheadline).foregroundStyle(.tertiary)
                InfoTooltip(text: tooltip)
            }
            Text("\u{2014}").font(.subheadline.weight(.medium)).foregroundStyle(.tertiary)
        }
    }

    private var vigorousMomentsTooltip: String {
        "Brief bursts of vigorous movement during normal life \u{2014} a fast flight of stairs, a rushed uphill walk \u{2014} counted even outside a logged workout. The dot below compares today against your own recent daily average, built from completed days only. Needs a wearable that tracks heart rate continuously; on iPhone-only, this stays unavailable since there's no continuous signal to detect bursts from. Research links these brief bursts to lower mortality risk in people who don't otherwise exercise \u{2014} shown here for context, not as a target to hit."
    }

    private func statCell(_ label: String, _ display: String, value: Double, range: (low: Double, high: Double)?, tooltip: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.subheadline).foregroundStyle(.tertiary)
                if let tooltip {
                    InfoTooltip(text: tooltip)
                }
            }
            Text(display).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            LowHighIndicator(value: value, low: range?.low ?? value, high: range?.high ?? value, width: 70, dotDiameter: 9)
        }
    }

    /// Active energy plus whichever resting-energy estimate is
    /// currently selected in Resting energy — a computed property
    /// rather than a value baked in by `refresh()` so it updates
    /// immediately when that selection changes in the other section,
    /// without needing this view to re-fetch or re-appear.
    private var totalCalories: Double? {
        guard let activeCalories else { return nil }
        let restingEstimate = restingEnergyPreference.value == .katchMcArdle ? (katchToday ?? appleRestingEstimate) : appleRestingEstimate
        guard let restingEstimate else { return nil }
        return activeCalories + restingEstimate
    }

    private var totalCaloriesRange: (low: Double, high: Double)? {
        guard !activeCaloriesHistoryRaw.isEmpty, activeCaloriesHistoryRaw.count == basalHistoryRaw.count else { return nil }
        // Katch-McArdle has no daily history of its own (lean mass
        // doesn't change meaningfully day to day), so its resting
        // contribution is approximated as today's value held constant
        // across the week — reasonable since body composition is
        // slow-moving, unlike Apple's own basal estimate which already
        // varies per day.
        let dailyResting: [Double]
        if restingEnergyPreference.value == .katchMcArdle, let katchToday {
            dailyResting = Array(repeating: katchToday, count: basalHistoryRaw.count)
        } else {
            dailyResting = basalHistoryRaw
        }
        return Self.minMax(zip(activeCaloriesHistoryRaw, dailyResting).map(+))
    }

    /// Low/high bounds from whatever days of history are actually
    /// available — as few as zero. With no history there's nothing to
    /// compare against, so the caller falls back to the current value
    /// as both bounds, which centers the dot. With enough days to spare
    /// one from each end, the single most extreme day is dropped before
    /// taking the bounds — at a 7-day window, a percentage-based trim
    /// (5th/95th percentile) rounds down to zero effective trim, so a
    /// lone unusually good or bad day would otherwise stretch the scale
    /// so far that every ordinary day, including today, reads as
    /// bunched at one end.
    private static func minMax(_ history: [Double], filterPositive: Bool = true) -> (low: Double, high: Double)? {
        let values = (filterPositive ? history.filter { $0 > 0 } : history).sorted()
        guard !values.isEmpty else { return nil }
        if values.count >= 5 {
            return (values[1], values[values.count - 2])
        }
        return (values.first!, values.last!)
    }

    private func refresh() async {
        async let stepsVal = healthKit.fetchTodayValue(for: .steps)
        async let distanceVal = healthKit.fetchTodayValue(for: .distance)
        async let exerciseVal = healthKit.fetchTodayValue(for: .exerciseMinutes)
        async let standVal = healthKit.fetchTodayValue(for: .standMinutes)
        async let activeCalVal = healthKit.fetchTodayValue(for: .activeCalories)
        async let neatVal = healthKit.fetchTodayNEAT()
        async let stepsHistory = healthKit.fetchDailyTotals(for: .stepCount, unit: .count(), days: 28)
        async let distanceHistory = healthKit.fetchDailyTotals(for: .distanceWalkingRunning, unit: .meter(), days: 7)
        async let exerciseHistory = healthKit.fetchDailyTotals(for: .appleExerciseTime, unit: .minute(), days: 7)
        async let standHistory = healthKit.fetchDailyTotals(for: .appleStandTime, unit: .minute(), days: 7)
        async let activeCaloriesHistory = healthKit.fetchDailyTotals(for: .activeEnergyBurned, unit: .kilocalorie(), days: 7)
        async let neatHistory = healthKit.fetchNEATHistory(days: 7)
        async let leanMassVal = healthKit.fetchLatestSample(for: .leanBodyMass, unit: .gramUnit(with: .kilo))
        async let basalHistory = healthKit.fetchDailyTotals(for: .basalEnergyBurned, unit: .kilocalorie(), days: 7)
        async let activeWeekFlags = healthKit.fetchActiveDayFlags(days: 7)
        async let strengthWeekFlags = healthKit.fetchStrengthDayFlags(days: 7)
        async let activeMonthFlags = healthKit.fetchActiveDayFlags(days: 28)
        async let strengthMonthFlags = healthKit.fetchStrengthDayFlags(days: 28)
        async let workouts = healthKit.fetchWorkouts(daysBack: 1)
        async let monthWorkoutsForVILPA = healthKit.fetchWorkouts(daysBack: 28)
        async let restingHRVal = healthKit.fetchTodayValue(for: .restingHeartRate)
        async let workoutHRSamples = healthKit.fetchWorkoutHeartRateSamples(daysBack: 90)
        async let todayHRSamples = healthKit.fetchTodayHeartRateSamples()
        async let monthHRSamples = healthKit.fetchHeartRateSamples(days: 28)

        steps = await stepsVal
        distance = await distanceVal
        exerciseMinutes = await exerciseVal
        standMinutes = await standVal
        activeCalories = await activeCalVal
        neat = await neatVal

        let history = await stepsHistory
        let positiveHistory = history.filter { $0 > 0 }.sorted()
        if positiveHistory.count >= 5 {
            let lowIndex = Int(Double(positiveHistory.count) * 0.05)
            let highIndex = min(positiveHistory.count - 1, Int(Double(positiveHistory.count) * 0.95))
            stepsRange = (positiveHistory[lowIndex], positiveHistory[highIndex])
        }

        distanceRange = Self.minMax(await distanceHistory)
        exerciseRange = Self.minMax(await exerciseHistory)
        standRange = Self.minMax(await standHistory)
        activeCaloriesRange = Self.minMax(await activeCaloriesHistory)
        neatRange = Self.minMax(await neatHistory)

        katchToday = (await leanMassVal).map { RMREngine.katchMcArdle(leanBodyMassKg: $0) }
        activeCaloriesHistoryRaw = await activeCaloriesHistory
        basalHistoryRaw = await basalHistory
        // Apple's basal-energy figure accrues linearly through the day,
        // so "today's" value is only ever a partial fraction until the
        // day ends — using it directly would make Total calories jump
        // upward all day for reasons that have nothing to do with
        // activity. The 7-day average of *completed* days (basalHistory
        // already excludes today) gives a stable full-day estimate
        // instead, the same fix applied to the Resting energy section —
        // median rather than mean so one low-coverage day doesn't drag
        // the figure down (see RMREngine.median).
        let positiveBasalHistory = basalHistoryRaw.filter { $0 > 0 }
        appleRestingEstimate = RMREngine.median(positiveBasalHistory)

        activeDaysWeek = await activeWeekFlags
        strengthDaysWeek = await strengthWeekFlags
        activeDaysMonth = await activeMonthFlags
        strengthDaysMonth = await strengthMonthFlags
        let allWorkouts = await workouts
        todaysWorkouts = allWorkouts.filter { Calendar.current.isDateInToday($0.startDate) }

        if let restingHR = await restingHRVal {
            let maxHR = MaxHeartRateEngine.resolve(
                observedWorkoutSamples: await workoutHRSamples,
                age: healthKit.fetchAge(),
                manualOverride: ManualMaxHeartRateStore.value
            )
            let workoutRanges = allWorkouts.map { $0.startDate...$0.startDate.addingTimeInterval($0.duration) }
            vigorousMoments = VILPADetector.countBursts(
                samples: await todayHRSamples, workoutRanges: workoutRanges,
                restingHR: restingHR, maxHR: maxHR.value
            )

            let monthWorkoutRanges = (await monthWorkoutsForVILPA).map { $0.startDate...$0.startDate.addingTimeInterval($0.duration) }
            let monthlyCounts = VILPADetector.dailyBurstCounts(
                samples: await monthHRSamples, workoutRanges: monthWorkoutRanges,
                restingHR: restingHR, maxHR: maxHR.value, days: 28
            )
            vigorousMomentsRange = Self.minMax(monthlyCounts.suffix(7).map(Double.init), filterPositive: false)
        }
    }
}
