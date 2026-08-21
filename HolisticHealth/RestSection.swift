import SwiftUI

struct RestSection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @State private var asleepHours: Double?
    @State private var efficiency: Double?
    @State private var sleepScore: Int?
    @State private var afterWorkout = false
    @State private var weekRegularity: SleepRegularity.Summary?
    @State private var monthRegularity: SleepRegularity.Summary?
    @State private var weekWakeRegularity: SleepRegularity.Summary?
    @State private var monthWakeRegularity: SleepRegularity.Summary?
    @State private var durationRange: (low: Double, high: Double)?
    @State private var scoreRange: (low: Double, high: Double)?
    @State private var weekAvgDuration: Double?
    @State private var weekAvgScore: Double?
    @State private var monthAvgDuration: Double?
    @State private var monthAvgScore: Double?
    @State private var monthDurationRange: (low: Double, high: Double)?
    @State private var monthScoreRange: (low: Double, high: Double)?
    @State private var lastNightBedStart: Date?
    @State private var lastNightWakeEnd: Date?
    @State private var weekSRI: SRIEngine.WindowResult?
    @State private var monthSRI: SRIEngine.WindowResult?
    @State private var weekSRIRange: (low: Double, high: Double)?
    @State private var monthSRIRange: (low: Double, high: Double)?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: LifeArea.sleep.systemImage)
                    .foregroundStyle(LifeArea.sleep.tint)
                Text("Rest").font(.title3.weight(.semibold))
                Spacer()
                Text("Today").font(.subheadline).foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(asleepHours.map { String(format: "%.1f hrs", $0) } ?? "\u{2014}")
                        .font(.title.weight(.medium))
                    Text("Duration").font(.subheadline).foregroundStyle(.tertiary)
                    if let asleepHours {
                        LowHighIndicator(value: asleepHours, low: durationRange?.low ?? asleepHours, high: durationRange?.high ?? asleepHours)
                    }
                }

                if let sleepScore {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text("\(sleepScore)/100")
                                .font(.title.weight(.medium))
                            InfoTooltip(text: "Weighted the same way Apple's own Sleep Score is: half from how long you slept, just under a third from how close your bedtime was to your usual, and the rest from how much you woke up overnight.")
                        }
                        Text("Score").font(.subheadline).foregroundStyle(.tertiary)
                        LowHighIndicator(
                            value: Double(sleepScore),
                            low: scoreRange?.low ?? Double(sleepScore),
                            high: scoreRange?.high ?? Double(sleepScore)
                        )
                    }
                }
            }

            if asleepHours == nil {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: timeColumns, alignment: .leading, spacing: 10) {
                    timeCell("Bedtime", value: lastNightBedStart, range: nil)
                    timeCell("Wake", value: lastNightWakeEnd, range: nil)
                }
            }

            if let efficiency {
                Text("\(Int(efficiency))% efficiency")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if afterWorkout {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                    Text("Sleep may have been affected by a workout earlier")
                        .font(.subheadline)
                }
                .foregroundStyle(.tertiary)
            }

            HStack {
                Text("This week").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
            }
            durationScoreGrid(avgDuration: weekAvgDuration, durationRange: durationRange, avgScore: weekAvgScore, scoreRange: scoreRange)
            timeRegularityGrid(bedtime: weekRegularity, wake: weekWakeRegularity)
            sriRow(result: weekSRI, range: weekSRIRange, showFallback: weekRegularity != nil || weekWakeRegularity != nil)

            HStack {
                Text("This month").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
            }
            durationScoreGrid(avgDuration: monthAvgDuration, durationRange: monthDurationRange, avgScore: monthAvgScore, scoreRange: monthScoreRange)
            timeRegularityGrid(bedtime: monthRegularity, wake: monthWakeRegularity)
            sriRow(result: monthSRI, range: monthSRIRange, showFallback: monthRegularity != nil || monthWakeRegularity != nil)
        }
        .task { await refresh() }
    }

    private var timeColumns: [GridItem] {
        [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    }

    @ViewBuilder
    private func durationScoreGrid(avgDuration: Double?, durationRange: (low: Double, high: Double)?,
                                    avgScore: Double?, scoreRange: (low: Double, high: Double)?) -> some View {
        if avgDuration != nil || avgScore != nil {
            LazyVGrid(columns: timeColumns, alignment: .leading, spacing: 10) {
                statCell(
                    "Avg. duration",
                    display: avgDuration.map { String(format: "%.1f hrs", $0) },
                    range: durationRange.map { String(format: "%.1f\u{2013}%.1f hrs", $0.low, $0.high) }
                )
                statCell(
                    "Avg. score",
                    display: avgScore.map { "\(Int($0.rounded()))/100" },
                    range: scoreRange.map { "\(Int($0.low))\u{2013}\(Int($0.high))" }
                )
            }
        }
    }

    @ViewBuilder
    private func statCell(_ label: String, display: String?, range: String?) -> some View {
        if let display {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(.tertiary)
                Text(display).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if let range {
                    Text(range).font(.subheadline).foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// `showFallback` mirrors the same suppression `regularityLine` used
    /// before it: only say "not enough nights yet" once per window —
    /// if the bedtime/wake grid above already said so, SRI (which needs
    /// strictly more data, at least one valid night-to-night pair) would
    /// otherwise repeat the identical message right underneath it.
    @ViewBuilder
    private func sriRow(result: SRIEngine.WindowResult?, range: (low: Double, high: Double)?, showFallback: Bool) -> some View {
        if let result {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(String(format: "%.0f", result.value))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("SRI").font(.subheadline).foregroundStyle(.tertiary)
                    InfoTooltip(text: sriTooltip)
                }
                LowHighIndicator(
                    value: result.value,
                    low: range?.low ?? result.value,
                    high: range?.high ?? result.value,
                    width: 70, dotDiameter: 9
                )
                Text("from \(result.nightsUsed) nights")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        } else if showFallback {
            Text("Not enough nights yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sriTooltip: String {
        "Sleep Regularity Index (Phillips et al.) measures how similar your sleep schedule is from one night to the next, on a scale from -100 (a completely different schedule every night) to +100 (identical every night) \u{2014} a different lens from the median/earliest/latest times above, which describe when you sleep rather than how consistent that timing is. Some published research has found sleep regularity predicts mortality risk more strongly than sleep duration alone in certain analyses, using a threshold around 70 \u{2014} shown here only as context, not as a target: this number is compared only against your own recent history, the same as everything else in this app."
    }

    @ViewBuilder
    private func timeRegularityGrid(bedtime: SleepRegularity.Summary?, wake: SleepRegularity.Summary?) -> some View {
        if bedtime == nil && wake == nil {
            Text("Not enough nights yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: timeColumns, alignment: .leading, spacing: 10) {
                timeCell("Bedtime", value: bedtime?.median, range: bedtime.map { ($0.earliest, $0.latest) })
                timeCell("Wake", value: wake?.median, range: wake.map { ($0.earliest, $0.latest) })
            }
        }
    }

    @ViewBuilder
    private func timeCell(_ label: String, value: Date?, range: (earliest: Date, latest: Date)?) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(.tertiary)
                Text(Self.timeFormatter.string(from: value)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if let range {
                    Text("\(Self.timeFormatter.string(from: range.earliest))\u{2013}\(Self.timeFormatter.string(from: range.latest))")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Low/high bounds from whatever nights of history are actually
    /// available — as few as zero. With no history there's nothing to
    /// compare against, so the caller falls back to the current value
    /// as both bounds, which centers the dot. With enough nights to
    /// spare one from each end, the single most extreme night is
    /// dropped before taking the bounds — at a 7-night window, a
    /// percentage-based trim (5th/95th percentile) rounds down to zero
    /// effective trim, so one unusually good or bad night would
    /// otherwise stretch the scale so far that every ordinary night,
    /// including last night, reads as bunched at one end.
    private static func minMax(_ history: [Double], filterPositive: Bool = true) -> (low: Double, high: Double)? {
        let values = (filterPositive ? history.filter { $0 > 0 } : history).sorted()
        guard !values.isEmpty else { return nil }
        if values.count >= 5 {
            return (values[1], values[values.count - 2])
        }
        return (values.first!, values.last!)
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Apple-style score per night (see SleepScoreEngine), judged
    /// against `usualBedtime` — pass the window's own median so a
    /// month's nights are judged against the month's usual bedtime,
    /// not the week's.
    private static func nightlyScores(nights: [HealthKitManager.SleepNightSummary], usualBedtime: Date?) -> [Double] {
        nights.map { night -> Double in
            let varianceMinutes: Double
            if let usualBedtime, let bedStart = night.bedStart {
                varianceMinutes = SleepRegularity.minutesApart(usualBedtime, bedStart)
            } else {
                varianceMinutes = 0
            }
            return Double(SleepScoreEngine.score(
                asleepHours: night.asleepHours,
                bedtimeVarianceMinutes: varianceMinutes,
                interruptionMinutes: night.interruptionMinutes
            ))
        }
    }

    private struct SRIResult {
        let week: SRIEngine.WindowResult?
        let month: SRIEngine.WindowResult?
        let weekRange: (low: Double, high: Double)?
        let monthRange: (low: Double, high: Double)?
    }

    /// Builds midnight-to-midnight calendar-day epoch profiles from the
    /// raw sleep samples, then computes both SRI windows plus a sliding
    /// history of each — 7-day SRI needs a trailing 8 days, 28-day SRI
    /// needs a trailing 29, and "today" is never included since it's
    /// still in progress (same completed-data rule used everywhere else
    /// in this app).
    private static func computeSRI(samples: [(start: Date, end: Date, value: Int)]) -> SRIResult {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date()
        let orderedDays: [Date] = (0..<45).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: yesterday)
        }

        let profiles = SRIEngine.dailyEpochProfiles(samples: samples, days: orderedDays)

        let week = orderedDays.count >= 8
            ? SRIEngine.windowSRI(profiles: profiles, orderedDays: Array(orderedDays.suffix(8)))
            : nil
        let month = orderedDays.count >= 29
            ? SRIEngine.windowSRI(profiles: profiles, orderedDays: Array(orderedDays.suffix(29)))
            : nil

        let weekHistory = SRIEngine.slidingWindowHistory(profiles: profiles, allDaysOldestToNewest: orderedDays, windowLength: 8)
        let monthHistory = SRIEngine.slidingWindowHistory(profiles: profiles, allDaysOldestToNewest: orderedDays, windowLength: 29)

        return SRIResult(
            week: week, month: month,
            weekRange: Self.minMax(weekHistory, filterPositive: false),
            monthRange: Self.minMax(monthHistory, filterPositive: false)
        )
    }

    private func refresh() async {
        async let today = healthKit.fetchTodaySleepSummary()
        async let weekNights = healthKit.fetchSleepNights(days: 7)
        async let monthNights = healthKit.fetchSleepNights(days: 28)
        async let workouts = healthKit.fetchWorkouts(daysBack: 2)
        // 45 days covers both a 7-day SRI window (needs 8 days) with
        // enough trailing history to build a real personal range around
        // it, and a 28-day SRI window (needs 29 days) with at least a
        // handful of points behind it too.
        async let sleepSamples = healthKit.fetchSleepCategorySamples(days: 45)

        if let todaySummary = await today {
            asleepHours = todaySummary.asleepHours
            if todaySummary.inBedHours > 0 {
                efficiency = min(100, (todaySummary.asleepHours / todaySummary.inBedHours) * 100)
            }
        }

        let week = await weekNights
        let month = await monthNights

        weekRegularity = SleepRegularity.summarize(times: week.compactMap(\.bedStart))
        monthRegularity = SleepRegularity.summarize(times: month.compactMap(\.bedStart))
        weekWakeRegularity = SleepRegularity.summarize(times: week.compactMap(\.wakeEnd))
        monthWakeRegularity = SleepRegularity.summarize(times: month.compactMap(\.wakeEnd))

        durationRange = Self.minMax(week.map(\.asleepHours))
        monthDurationRange = Self.minMax(month.map(\.asleepHours))
        weekAvgDuration = Self.average(week.map(\.asleepHours))
        monthAvgDuration = Self.average(month.map(\.asleepHours))

        let sri = Self.computeSRI(samples: await sleepSamples)
        weekSRI = sri.week
        monthSRI = sri.month
        weekSRIRange = sri.weekRange
        monthSRIRange = sri.monthRange

        // Each window's nights are judged against that same window's own
        // usual bedtime, matching how the rest of the app treats "usual"
        // as window-relative rather than borrowing the week's figure for
        // a month-long comparison.
        let weekScores = Self.nightlyScores(nights: week, usualBedtime: weekRegularity?.median)
        let monthScores = Self.nightlyScores(nights: month, usualBedtime: monthRegularity?.median)
        scoreRange = Self.minMax(weekScores, filterPositive: false)
        monthScoreRange = Self.minMax(monthScores, filterPositive: false)
        weekAvgScore = Self.average(weekScores)
        monthAvgScore = Self.average(monthScores)

        if let lastNight = month.last {
            lastNightBedStart = lastNight.bedStart
            lastNightWakeEnd = lastNight.wakeEnd

            let varianceMinutes: Double
            if let median = weekRegularity?.median, let bedStart = lastNight.bedStart {
                varianceMinutes = SleepRegularity.minutesApart(median, bedStart)
            } else {
                varianceMinutes = 0
            }

            sleepScore = SleepScoreEngine.score(
                asleepHours: lastNight.asleepHours,
                bedtimeVarianceMinutes: varianceMinutes,
                interruptionMinutes: lastNight.interruptionMinutes
            )

            if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: lastNight.date) {
                afterWorkout = (await workouts).contains {
                    Calendar.current.isDate($0.startDate, inSameDayAs: yesterday) && $0.duration >= 45 * 60
                }
            }
        }
    }
}
