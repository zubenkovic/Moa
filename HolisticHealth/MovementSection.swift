import SwiftUI
import HealthKit

struct MovementSection: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var restingEnergyPreference = RestingEnergyPreferenceStore.shared

    @State private var steps: Double?
    @State private var distance: Double?
    @State private var exerciseMinutes: Double?
    @State private var strengthMinutes: Double?
    @State private var activeCalories: Double?
    @State private var neat: Double?
    @State private var appleRestingEstimate: Double?
    @State private var katchToday: Double?
    @State private var activeCaloriesHistoryRaw: [Double] = []
    @State private var basalHistoryRaw: [Double] = []
    @State private var stepsRange: (low: Double, high: Double)?
    @State private var distanceRange: (low: Double, high: Double)?
    @State private var exerciseRange: (low: Double, high: Double)?
    @State private var strengthMinutesRange: (low: Double, high: Double)?
    @State private var activeCaloriesRange: (low: Double, high: Double)?
    @State private var neatRange: (low: Double, high: Double)?
    @State private var vigorousMomentsRange: (low: Double, high: Double)?
    @State private var weekAvgSteps: Double?
    @State private var monthAvgSteps: Double?
    @State private var weekTotalDistance: Double?
    @State private var monthTotalDistance: Double?
    @State private var weekCardioMinutes: Double?
    @State private var monthCardioMinutes: Double?
    @State private var weekStrengthMinutesTotal: Double?
    @State private var monthStrengthMinutesTotal: Double?
    @State private var weekAvgActiveCalories: Double?
    @State private var monthAvgActiveCalories: Double?
    @State private var todaysWorkouts: [HealthKitManager.WorkoutSummary] = []
    @State private var workoutDetails: [UUID: WorkoutDetail] = [:]
    @State private var weekTypeSummaries: [WorkoutTypeSummary] = []
    @State private var monthTypeSummaries: [WorkoutTypeSummary] = []
    @State private var vigorousMoments: Int?

    /// Per-workout average heart rate (every type) and zone breakdown
    /// (cardio types only — see `WorkoutSummary.isCardio`).
    private struct WorkoutDetail {
        let avgHR: Double?
        let zones: HeartRateZoneEngine.ZoneBreakdown?
    }

    /// One row of the "This week/month workouts" breakdown — every
    /// workout of a given type in the window, reduced to a count and
    /// whichever averages actually apply to that type (distance for
    /// running/cycling/swimming/hiking, HR wherever samples exist,
    /// calories wherever HealthKit reported them).
    private struct WorkoutTypeSummary: Identifiable {
        var id: String { typeName }
        let typeName: String
        let count: Int
        let avgDurationMinutes: Double
        let avgDistanceMeters: Double?
        let avgCalories: Double?
        let avgHR: Double?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: LifeArea.movement.systemImage)
                    .foregroundStyle(LifeArea.movement.tint)
                Text("Movement").font(.title3.weight(.semibold))
                Spacer()
                Text("Today").statLabelStyle()
            }

            HStack(spacing: 2) {
                Text(steps.map { "\(NumberFormat.int($0))/\(NumberFormat.int(Self.stepGoal)) steps" } ?? "No data yet")
                    .headlineValueStyle()
                InfoTooltip(text: Self.stepGoalTooltip)
            }

            if let steps, let range = stepsRange {
                LowHighIndicator(value: steps, low: range.low, high: range.high, label: "Steps")
            }

            statGrid

            if !todaysWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today's workouts").statLabelStyle()
                    ForEach(todaysWorkouts) { workout in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(workout.typeName)
                                Spacer()
                                Text("\(NumberFormat.int(workout.duration / 60)) min")
                                if let cal = workout.totalEnergyBurned {
                                    Text("\u{00B7} \(NumberFormat.int(cal)) kcal")
                                }
                            }
                            .statValueStyle()
                            .foregroundStyle(.secondary)

                            if let avgHR = workoutDetails[workout.id]?.avgHR {
                                Text("Avg HR \(NumberFormat.int(avgHR)) bpm")
                                    .supportingTextStyle()
                            }

                            if let zones = workoutDetails[workout.id]?.zones, let summary = zoneSummary(zones) {
                                Text(summary)
                                    .supportingTextStyle()
                            }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("This week").sectionHeadingStyle()
                Spacer()
            }
            VStack(alignment: .leading, spacing: 12) {
                weeklyTargetsGrid(cardioMinutes: weekCardioMinutes, strengthMinutes: weekStrengthMinutesTotal, perWeek: false)
                averagesGrid(steps: weekAvgSteps, distance: weekTotalDistance, activeCalories: weekAvgActiveCalories)
                typeSummaryList(weekTypeSummaries)
            }

            Divider()
            HStack {
                Text("This month").sectionHeadingStyle()
                Spacer()
            }
            VStack(alignment: .leading, spacing: 12) {
                weeklyTargetsGrid(cardioMinutes: monthCardioMinutes, strengthMinutes: monthStrengthMinutesTotal, perWeek: true)
                averagesGrid(steps: monthAvgSteps, distance: monthTotalDistance, activeCalories: monthAvgActiveCalories)
                typeSummaryList(monthTypeSummaries)
            }
        }
        .task { await refresh() }
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
            if let exerciseMinutes {
                statCell("Cardio minutes", "\(NumberFormat.int(exerciseMinutes)) min", value: exerciseMinutes, range: exerciseRange)
            }
            // `fetchStrengthMinutes` sums a workout list and can only ever
            // return a real Double, never nil — zero workouts sums to
            // 0.0, indistinguishable at that layer from "confirmed zero
            // minutes today." Gating on `steps` (sourced from
            // `fetchTodayValue`, which genuinely returns nil when there's
            // no data at all) uses the one metric in this grid that
            // reliably signals "do we have real HealthKit data today,"
            // so this doesn't show a misleading "0 min" next to cells
            // that are correctly hiding themselves in the same no-data state.
            // Replaces the old "Stood" (Apple Stand minutes) cell that
            // used to sit here — Stand time is still tracked and still
            // shown, just one tap deeper via `LifeAreaDetailView`
            // (`LifeArea.movement.detailMetrics` still lists it), since
            // this grid only has room for the metrics with the most
            // actionable research behind them at a glance.
            if steps != nil, let strengthMinutes {
                statCell("Strength minutes", "\(NumberFormat.int(strengthMinutes)) min", value: strengthMinutes, range: strengthMinutesRange)
            }
            if let distance {
                statCell("Distance", "\(NumberFormat.decimal1(distance / 1000)) km", value: distance, range: distanceRange)
            }
            if let activeCalories {
                statCell("Active energy", "\(NumberFormat.int(activeCalories)) kcal", value: activeCalories, range: activeCaloriesRange)
            }
            if let neat {
                statCell("Non-exercise", "~\(NumberFormat.int(neat)) kcal", value: neat, range: neatRange)
            }
            if let totalCalories {
                statCell(
                    "Total calories", "\(NumberFormat.int(totalCalories)) kcal", value: totalCalories, range: totalCaloriesRange,
                    tooltip: "Active energy plus your resting energy estimate (whichever one is selected in Resting energy \u{2014} tap either number there to switch)."
                )
            }
            // Same `steps`-as-signal gate as Strength minutes above — but
            // only for the true no-data case. A real phone-only user
            // (no wearable) still has step data, so they still see this
            // cell's tooltip and learn the feature exists, same as
            // `unavailableStatCell`'s doc comment intends; this only
            // suppresses it when there's no HealthKit data at all.
            if steps != nil {
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
    }

    /// Same label/tooltip treatment as a normal stat cell, but for when
    /// there's nothing to plot — no bar, no invented number. Keeping
    /// this visible (rather than hiding the whole stat) matters even for
    /// phone-only users with no wearable: the tooltip is the only place
    /// they'd learn the feature exists and why it isn't showing a value.
    private func unavailableStatCell(_ label: String, tooltip: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(label).statLabelStyle()
                InfoTooltip(text: tooltip)
            }
            Text("\u{2014}").statValueStyle().foregroundStyle(.tertiary)
        }
    }

    /// The live headline pairs this with the user's own step count, so it
    /// needs the same per-Region grouping — a German phone showing
    /// "8.412" next to a hand-typed "7,000" would look like a typo, not a
    /// design choice. The tooltip body's numbers stay as plain English
    /// prose below: this app has no localization system, so surrounding
    /// sentence text is English regardless of Region, and a formatted
    /// "7.000" sitting inside "10,000 steps comes from..." would read
    /// as inconsistent with the rest of that sentence, not more correct.
    private static let stepGoal = 7000

    /// 10,000 has no research basis — it comes from a 1965 Japanese
    /// pedometer ad ("manpo-kei", literally "10,000-steps meter"), not a
    /// study. 7,000 is used instead: Paluch et al.'s 2022 pooled
    /// meta-analysis of 15 cohort studies (~50,000 adults, Lancet Public
    /// Health) found mortality-risk reduction leveling off around
    /// 7,000\u{2013}8,000 steps/day, with only marginal gains beyond that.
    private static let stepGoalTooltip = "10,000 steps comes from a 1965 Japanese pedometer ad, not research. Paluch et al.'s 2022 meta-analysis of 15 cohort studies (~50,000 adults, Lancet Public Health) found mortality risk leveling off around 7,000\u{2013}8,000 steps a day, with only marginal gains beyond that. Used here as a research-informed reference point, not a target to hit."

    private var vigorousMomentsTooltip: String {
        "Brief bursts of vigorous movement during normal life \u{2014} a fast flight of stairs, a rushed uphill walk \u{2014} counted even outside a logged workout. The dot below compares today against your own recent daily average, built from completed days only. Needs a wearable that tracks heart rate continuously; on iPhone-only, this stays unavailable since there's no continuous signal to detect bursts from. Stamatakis et al., 2022, Nature Medicine, linked these brief bursts to lower mortality risk in people who don't otherwise exercise \u{2014} shown here for context, not as a target to hit."
    }

    /// Compact "Z2 14m · Z3 6m" summary for a workout row — same Z1-Z5
    /// Karvonen zones explained in full in HeartSection's tooltip;
    /// zones under 30 seconds are dropped as noise rather than shown as
    /// "0m".
    private func zoneSummary(_ zones: HeartRateZoneEngine.ZoneBreakdown) -> String? {
        let entries = [
            ("Z1", zones.zone1Minutes), ("Z2", zones.zone2Minutes), ("Z3", zones.zone3Minutes),
            ("Z4", zones.zone4Minutes), ("Z5", zones.zone5Minutes),
        ].filter { $0.1 >= 0.5 }
        guard !entries.isEmpty else { return nil }
        return entries.map { "\($0.0) \(NumberFormat.int($0.1))m" }.joined(separator: " \u{00B7} ")
    }

    /// Cardio and Strength minutes, plain text against the exact same
    /// weekly targets `ActivityIndexEngine` benchmarks (150/60) — no
    /// fill bar, no day-count tracking alongside them anymore. Active/
    /// Strength "days" were dropped entirely: now that actual minutes
    /// against a real target are shown, a binary day-count answered a
    /// coarser version of the same question. There's no established
    /// cardio:strength ratio in the research to weight these against
    /// each other, so each is shown against its own independent target
    /// instead, same as Activity Index already does. `perWeek` labels
    /// the month figure as a rate ("min/week") rather than a raw
    /// 28-day total, since the underlying number is already the
    /// weekly-equivalent (28-day total \u{00F7} 4) computed in `refresh()` —
    /// the label just makes that explicit instead of implying it's a
    /// literal achieved total.
    @ViewBuilder
    private func weeklyTargetsGrid(cardioMinutes: Double?, strengthMinutes: Double?, perWeek: Bool) -> some View {
        if cardioMinutes != nil || strengthMinutes != nil {
            let suffix = perWeek ? "/week" : ""
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                if let cardioMinutes {
                    averageCell(
                        "Cardio minutes", "\(NumberFormat.int(cardioMinutes))/\(NumberFormat.int(ActivityIndexEngine.minutesTarget)) min\(suffix)",
                        tooltip: Self.cardioMinutesTooltip
                    )
                }
                if let strengthMinutes {
                    averageCell(
                        "Strength minutes", "\(NumberFormat.int(strengthMinutes))/\(NumberFormat.int(ActivityIndexEngine.strengthTarget)) min\(suffix)",
                        tooltip: Self.strengthMinutesTooltip
                    )
                }
            }
        }
    }

    /// Same label/value stat-cell language as Today's `statGrid`, reused
    /// for the week/month windows. Distance is the window's own genuine
    /// total (7-day sum for week, 28-day sum for month) rather than a
    /// daily average or a weekly-equivalent rate — unlike Cardio/
    /// Strength minutes, there's no fixed weekly research target to
    /// stay comparable to, so there's no reason to normalize it the
    /// same way; each window just reports its own real mileage, the
    /// way a runner actually tracks it ("42 km this week"), not a
    /// daily average nobody mentally computes.
    @ViewBuilder
    private func averagesGrid(steps: Double?, distance: Double?, activeCalories: Double?) -> some View {
        if steps != nil || distance != nil || activeCalories != nil {
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                if let steps { averageCell("Avg steps", NumberFormat.int(steps)) }
                if let distance { averageCell("Total distance", "\(NumberFormat.decimal1(distance / 1000)) km") }
                if let activeCalories { averageCell("Avg active energy", "\(NumberFormat.int(activeCalories)) kcal") }
            }
        }
    }

    private func averageCell(_ label: String, _ display: String, tooltip: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(label).statLabelStyle()
                if let tooltip {
                    InfoTooltip(text: tooltip)
                }
            }
            Text(display).statValueStyle()
        }
    }

    private static let cardioMinutesTooltip = "150 min/week of moderate-or-more aerobic activity comes from WHO's 2020 physical activity guidelines (Bull et al., British Journal of Sports Medicine). Not capped \u{2014} exceeding it just shows as the real number."

    private static let strengthMinutesTooltip = "A 2022 meta-analysis (Shailendra et al., American Journal of Preventive Medicine) found resistance training's largest mortality-risk reduction \u{2014} 27% \u{2014} around 60 min/week, leveling off beyond that. Not capped \u{2014} exceeding it just shows as the real number."

    /// Same tinted rounded container HeartSection's Z1\u{2013}Z5 zone
    /// breakdown already uses — without it, this list just started
    /// bare right after a grid of compact stat cells, a sudden shift
    /// from tidy boxes to a loose block of text that read as bolted on
    /// rather than part of the same card.
    @ViewBuilder
    private func typeSummaryList(_ summaries: [WorkoutTypeSummary]) -> some View {
        if !summaries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(summaries) { typeSummaryRow($0) }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func typeSummaryRow(_ summary: WorkoutTypeSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: Self.icon(for: summary.typeName))
                    .font(.system(size: 14))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.secondary)
                Text(summary.typeName)
                Spacer()
                Text("\(summary.count)")
            }
            .statValueStyle()
            .foregroundStyle(.secondary)

            Text(typeSummaryDetailLine(summary))
                .supportingTextStyle()
        }
    }

    /// Matches `WorkoutSummary.typeName`'s exact strings — ties this
    /// list back into the icon-forward language every section header
    /// already uses, instead of reading as a plain list of gray text.
    private static func icon(for typeName: String) -> String {
        switch typeName {
        case "Running": return "figure.run"
        case "Walking": return "figure.walk"
        case "Cycling": return "figure.outdoor.cycle"
        case "Swimming": return "figure.pool.swim"
        case "Strength": return "figure.strengthtraining.traditional"
        case "Yoga": return "figure.yoga"
        case "HIIT": return "bolt.fill"
        case "Hiking": return "figure.hiking"
        case "Core": return "figure.core.training"
        case "Elliptical": return "figure.elliptical"
        case "Rowing": return "figure.rower"
        default: return "figure.mixed.cardio"
        }
    }

    /// "Avg: 105 min | 14.9 km" for types with a meaningful distance
    /// (running, cycling, swimming, hiking), "Avg: 45 min | 287 kcal"
    /// for those without one (strength, yoga, HIIT, core) — one
    /// secondary stat chosen for relevance rather than every stat
    /// HealthKit happens to have, and HR dropped from this rollup line
    /// entirely as the least essential of the four.
    private func typeSummaryDetailLine(_ summary: WorkoutTypeSummary) -> String {
        let duration = "\(NumberFormat.int(summary.avgDurationMinutes)) min"
        if let avgDistanceMeters = summary.avgDistanceMeters {
            return "Avg: \(duration) | \(NumberFormat.decimal1(avgDistanceMeters / 1000)) km"
        }
        if let avgCalories = summary.avgCalories {
            return "Avg: \(duration) | \(NumberFormat.int(avgCalories)) kcal"
        }
        return "Avg: \(duration)"
    }

    private func statCell(_ label: String, _ display: String, value: Double, range: (low: Double, high: Double)?, tooltip: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 2) {
                Text(label).statLabelStyle()
                if let tooltip {
                    InfoTooltip(text: tooltip)
                }
            }
            Text(display).statValueStyle()
            LowHighIndicator(value: value, low: range?.low ?? value, high: range?.high ?? value, width: 70, dotDiameter: 9, label: label)
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

    /// Same completed-days-only convention as everywhere else in this
    /// app — zero/no-data days are excluded rather than dragging the
    /// average down, since they represent missing data, not genuinely
    /// zero activity.
    private static func average(_ history: [Double]) -> Double? {
        let values = history.filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Groups a window's workouts by type, reducing each group to a
    /// count and whichever averages have data — distance, calories, and
    /// HR are each nil'd out per-group rather than averaged over zero
    /// or averaged with missing entries silently treated as zero.
    /// Sorted by count descending (busiest activity first), ties broken
    /// alphabetically for a stable order.
    private static func summarizeByType(
        _ workouts: [HealthKitManager.WorkoutSummary], hrSamplesById: [UUID: [(date: Date, bpm: Double)]]
    ) -> [WorkoutTypeSummary] {
        let grouped = Dictionary(grouping: workouts, by: \.typeName)
        return grouped.map { typeName, items in
            let avgDurationMinutes = items.map(\.duration).reduce(0, +) / Double(items.count) / 60

            let distances = items.compactMap(\.distance)
            let avgDistanceMeters = distances.isEmpty ? nil : distances.reduce(0, +) / Double(distances.count)

            let calories = items.compactMap(\.totalEnergyBurned)
            let avgCalories = calories.isEmpty ? nil : calories.reduce(0, +) / Double(calories.count)

            let hrAverages = items.compactMap { workout -> Double? in
                let samples = hrSamplesById[workout.id] ?? []
                guard !samples.isEmpty else { return nil }
                return samples.map(\.bpm).reduce(0, +) / Double(samples.count)
            }
            let avgHR = hrAverages.isEmpty ? nil : hrAverages.reduce(0, +) / Double(hrAverages.count)

            return WorkoutTypeSummary(
                typeName: typeName, count: items.count, avgDurationMinutes: avgDurationMinutes,
                avgDistanceMeters: avgDistanceMeters, avgCalories: avgCalories, avgHR: avgHR
            )
        }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.typeName < $1.typeName }
    }

    private func refresh() async {
        async let stepsVal = healthKit.fetchTodayValue(for: .steps)
        async let distanceVal = healthKit.fetchTodayValue(for: .distance)
        async let exerciseVal = healthKit.fetchTodayValue(for: .exerciseMinutes)
        async let strengthMinutesVal = healthKit.fetchStrengthMinutes(days: 1)
        async let strengthMinutesHistory = healthKit.fetchStrengthMinutesHistory(days: 7)
        async let weekStrengthTotal = healthKit.fetchStrengthMinutes(days: 7)
        async let monthStrengthTotal = healthKit.fetchStrengthMinutes(days: 28)
        async let activeCalVal = healthKit.fetchTodayValue(for: .activeCalories)
        async let neatVal = healthKit.fetchTodayNEAT()
        async let stepsHistory = healthKit.fetchDailyTotals(for: .stepCount, unit: .count(), days: 28)
        // 28 days, summed across every distance-tracking activity type
        // (see `fetchDistanceHistory`) — used both for Today's range
        // (last 7 of these 28) and the new week/month averages below.
        async let distanceHistory28 = healthKit.fetchDistanceHistory(days: 28)
        async let exerciseHistory = healthKit.fetchDailyTotals(for: .appleExerciseTime, unit: .minute(), days: 7)
        async let exerciseHistory28 = healthKit.fetchDailyTotals(for: .appleExerciseTime, unit: .minute(), days: 28)
        async let activeCaloriesHistory = healthKit.fetchDailyTotals(for: .activeEnergyBurned, unit: .kilocalorie(), days: 7)
        async let activeCaloriesHistory28 = healthKit.fetchDailyTotals(for: .activeEnergyBurned, unit: .kilocalorie(), days: 28)
        async let neatHistory = healthKit.fetchNEATHistory(days: 7)
        async let leanMassVal = healthKit.fetchLatestSample(for: .leanBodyMass, unit: .gramUnit(with: .kilo))
        async let basalHistory = healthKit.fetchDailyTotals(for: .basalEnergyBurned, unit: .kilocalorie(), days: 7)
        async let monthWorkouts = healthKit.fetchWorkouts(daysBack: 28)
        async let restingHRVal = healthKit.fetchTodayValue(for: .restingHeartRate)
        async let workoutHRSamples = healthKit.fetchWorkoutHeartRateSamples(daysBack: 90)
        async let todayHRSamples = healthKit.fetchTodayHeartRateSamples()
        async let monthHRSamples = healthKit.fetchHeartRateSamples(days: 28)

        steps = await stepsVal
        distance = await distanceVal
        exerciseMinutes = await exerciseVal
        strengthMinutes = await strengthMinutesVal
        // Not `filterPositive` (the default): strength minutes are
        // legitimately zero on most days for most people, same as
        // Vigorous moments below — filtering those out would compute
        // the range from only the handful of training days, hiding how
        // sparse it actually is.
        strengthMinutesRange = Self.minMax(await strengthMinutesHistory, filterPositive: false)
        activeCalories = await activeCalVal
        neat = await neatVal

        let history = await stepsHistory
        let positiveHistory = history.filter { $0 > 0 }.sorted()
        if positiveHistory.count >= 5 {
            let lowIndex = Int(Double(positiveHistory.count) * 0.05)
            let highIndex = min(positiveHistory.count - 1, Int(Double(positiveHistory.count) * 0.95))
            stepsRange = (positiveHistory[lowIndex], positiveHistory[highIndex])
        }

        let distance28 = await distanceHistory28
        distanceRange = Self.minMax(Array(distance28.suffix(7)))
        weekTotalDistance = Array(distance28.suffix(7)).reduce(0, +)
        monthTotalDistance = distance28.reduce(0, +)

        exerciseRange = Self.minMax(await exerciseHistory)
        let exercise28 = await exerciseHistory28
        // Weekly total, not a daily average — this is compared against
        // ActivityIndexEngine's own 150-minute weekly target, the same
        // benchmark Activity Index uses, not an average with no target
        // to read against. Month uses the weekly-*equivalent* rate
        // (28-day total \u{00F7} 4) so it's comparable to the same weekly
        // benchmark rather than a scaled-up monthly one — matching
        // exactly how ActivityIndexSection.compute already handles its
        // own month window.
        //
        // `exercise28` comes from `fetchDailyTotals`, which deliberately
        // ends yesterday — but `weekStrengthMinutesTotal`/
        // `monthStrengthMinutesTotal` below come from
        // `fetchStrengthMinutes` → `fetchWorkouts(daysBack:)`, which
        // uses `Date()` and so does include today. Adding today's
        // already-fetched `exerciseMinutes` here keeps both figures on
        // the same window — otherwise a workout done today would show
        // up in "This week"'s Strength minutes immediately but not in
        // Cardio minutes until tomorrow.
        weekCardioMinutes = Array(exercise28.suffix(6)).reduce(0, +) + (exerciseMinutes ?? 0)
        monthCardioMinutes = (exercise28.reduce(0, +) + (exerciseMinutes ?? 0)) / 4

        weekStrengthMinutesTotal = await weekStrengthTotal
        monthStrengthMinutesTotal = (await monthStrengthTotal) / 4

        activeCaloriesRange = Self.minMax(await activeCaloriesHistory)
        let activeCalories28 = await activeCaloriesHistory28
        weekAvgActiveCalories = Self.average(Array(activeCalories28.suffix(7)))
        monthAvgActiveCalories = Self.average(activeCalories28)

        neatRange = Self.minMax(await neatHistory)

        weekAvgSteps = Self.average(Array(history.suffix(7)))
        monthAvgSteps = Self.average(history)

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

        let allMonthWorkouts = await monthWorkouts
        todaysWorkouts = allMonthWorkouts.filter { Calendar.current.isDateInToday($0.startDate) }
        let weekCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weekWorkouts = allMonthWorkouts.filter { $0.startDate >= weekCutoff }
        // Same "daysBack: 1" window the old dedicated today-fetch used —
        // slightly broader than the calendar day, so a workout just
        // before midnight still counts toward Vigorous Moments below.
        let oneDayCutoff = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let recentWorkouts = allMonthWorkouts.filter { $0.startDate >= oneDayCutoff }
        async let monthWorkoutHRSamples = healthKit.fetchHeartRateSamples(for: allMonthWorkouts)

        let restingHR = await restingHRVal
        let maxHR: MaxHeartRateEngine.Result? = restingHR == nil ? nil : MaxHeartRateEngine.resolve(
            observedWorkoutSamples: await workoutHRSamples,
            age: healthKit.fetchAge(),
            manualOverride: ManualMaxHeartRateStore.value
        )

        let samplesByWorkout = await monthWorkoutHRSamples
        workoutDetails = Dictionary(uniqueKeysWithValues: todaysWorkouts.map { workout in
            let samples = samplesByWorkout[workout.id] ?? []
            let avgHR = samples.isEmpty ? nil : samples.map(\.bpm).reduce(0, +) / Double(samples.count)
            let zones: HeartRateZoneEngine.ZoneBreakdown?
            if workout.isCardio, let restingHR, let maxHR {
                zones = HeartRateZoneEngine.breakdown(samples: samples, restingHR: restingHR, maxHR: maxHR.value)
            } else {
                zones = nil
            }
            return (workout.id, WorkoutDetail(avgHR: avgHR, zones: zones))
        })

        weekTypeSummaries = Self.summarizeByType(weekWorkouts, hrSamplesById: samplesByWorkout)
        monthTypeSummaries = Self.summarizeByType(allMonthWorkouts, hrSamplesById: samplesByWorkout)

        if let restingHR, let maxHR {
            let workoutRanges = recentWorkouts.map { $0.startDate...$0.startDate.addingTimeInterval($0.duration) }
            vigorousMoments = VILPADetector.countBursts(
                samples: await todayHRSamples, workoutRanges: workoutRanges,
                restingHR: restingHR, maxHR: maxHR.value
            )

            let monthWorkoutRanges = allMonthWorkouts.map { $0.startDate...$0.startDate.addingTimeInterval($0.duration) }
            let monthlyCounts = VILPADetector.dailyBurstCounts(
                samples: await monthHRSamples, workoutRanges: monthWorkoutRanges,
                restingHR: restingHR, maxHR: maxHR.value, days: 28
            )
            vigorousMomentsRange = Self.minMax(monthlyCounts.suffix(7).map(Double.init), filterPositive: false)
        }

        SectionLoadCoordinator.shared.markLoaded("Movement")
    }
}
