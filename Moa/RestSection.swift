import SwiftUI

struct RestSection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @State private var asleepHours: Double?
    @State private var efficiency: Double?
    @State private var afterWorkout = false
    @State private var weekRegularity: SleepRegularity.Summary?
    @State private var monthRegularity: SleepRegularity.Summary?
    @State private var weekWakeRegularity: SleepRegularity.Summary?
    @State private var monthWakeRegularity: SleepRegularity.Summary?
    @State private var durationRange: (low: Double, high: Double)?
    @State private var weekAvgDuration: Double?
    @State private var monthAvgDuration: Double?
    @State private var monthDurationRange: (low: Double, high: Double)?
    @State private var lastNightBedStart: Date?
    @State private var lastNightWakeEnd: Date?
    @State private var weekSRI: SRIEngine.WindowResult?
    @State private var monthSRI: SRIEngine.WindowResult?
    @State private var weekSRIRange: (low: Double, high: Double)?
    @State private var monthSRIRange: (low: Double, high: Double)?

    /// `.timeStyle = .short` rather than a hardcoded "h:mm a" — verified
    /// directly that this alone (with no other config) already renders
    /// "11:50 PM" in en_US but "23:50" in de_DE/en_GB/fr_FR/ja_JP, the
    /// same locale-preferred-hour-cycle mechanism the device's own
    /// "24-Hour Time" Settings toggle overrides, so this follows that
    /// toggle the same way the system clock does — same reasoning as
    /// `NumberFormat`'s `.autoupdatingCurrent` locale, just for time
    /// instead of numbers.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: LifeArea.sleep.systemImage)
                    .foregroundStyle(LifeArea.sleep.tint)
                Text("Rest").font(.title3.weight(.semibold))
                Spacer()
                Text("Today").statLabelStyle()
            }

            HStack(spacing: 2) {
                Text(asleepHours.map { "Sleep \(NumberFormat.decimal1($0)) hrs" } ?? "Sleep \u{2014}")
                    .headlineValueStyle()
                InfoTooltip(text: Self.sleepDurationTooltip)
            }
            if let asleepHours {
                LowHighIndicator(value: asleepHours, low: durationRange?.low ?? asleepHours, high: durationRange?.high ?? asleepHours, label: "Sleep duration")
            }

            if asleepHours == nil {
                Text("No data yet")
                    .emptyStateCaptionStyle()
            } else {
                LazyVGrid(columns: timeColumns, alignment: .leading, spacing: 10) {
                    timeCell("Bedtime", value: lastNightBedStart, range: nil)
                    timeCell("Wake", value: lastNightWakeEnd, range: nil)
                }
            }

            if let efficiency {
                Text("\(NumberFormat.int(efficiency))% efficiency")
                    .supportingTextStyle()
            }

            if afterWorkout {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("Sleep may have been affected by a workout earlier")
                }
                .supportingTextStyle()
            }

            Divider()
            HStack {
                Text("This week").sectionHeadingStyle()
                Spacer()
            }
            LazyVGrid(columns: timeColumns, alignment: .leading, spacing: 10) {
                statCell(
                    "Avg. duration",
                    display: weekAvgDuration.map { "\(NumberFormat.decimal1($0)) hrs" },
                    range: durationRange.map { "\(NumberFormat.decimal1($0.low))\u{2013}\(NumberFormat.decimal1($0.high)) hrs" }
                )
                sriRow(result: weekSRI, range: weekSRIRange, showFallback: weekRegularity != nil || weekWakeRegularity != nil)
            }
            timeRegularityGrid(bedtime: weekRegularity, wake: weekWakeRegularity)

            Divider()
            HStack {
                Text("This month").sectionHeadingStyle()
                Spacer()
            }
            LazyVGrid(columns: timeColumns, alignment: .leading, spacing: 10) {
                statCell(
                    "Avg. duration",
                    display: monthAvgDuration.map { "\(NumberFormat.decimal1($0)) hrs" },
                    range: monthDurationRange.map { "\(NumberFormat.decimal1($0.low))\u{2013}\(NumberFormat.decimal1($0.high)) hrs" }
                )
                sriRow(result: monthSRI, range: monthSRIRange, showFallback: monthRegularity != nil || monthWakeRegularity != nil)
            }
            timeRegularityGrid(bedtime: monthRegularity, wake: monthWakeRegularity)
        }
        .task { await refresh() }
    }

    private var timeColumns: [GridItem] {
        [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    }

    @ViewBuilder
    private func statCell(_ label: String, display: String?, range: String?) -> some View {
        if let display {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).statLabelStyle()
                Text(display).statValueStyle()
                if let range {
                    Text(range).supportingTextStyle()
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
                    Text(NumberFormat.int(result.value))
                        .statValueStyle()
                    HStack(spacing: 2) {
                        Text("SRI").statLabelStyle()
                        InfoTooltip(text: sriTooltip)
                    }
                }
                LowHighIndicator(
                    value: result.value,
                    low: range?.low ?? result.value,
                    high: range?.high ?? result.value,
                    width: 70, dotDiameter: 9,
                    label: "Sleep Regularity Index"
                )
                Text("from \(result.nightsUsed) nights")
                    .supportingTextStyle()
            }
        } else if showFallback {
            Text("Not enough nights yet")
                .emptyStateCaptionStyle()
        }
    }

    /// General education only \u{2014} the 7\u{2013}9 hour range and its
    /// research basis, never a claim about what tonight's specific
    /// number means for this person (the low-high indicator right below
    /// this headline already handles that, against their own history).
    private static let sleepDurationTooltip = "The 7\u{2013}9 hour range comes from the National Sleep Foundation's 2015 expert panel review (Hirshkowitz et al., Sleep Health), which found both shorter and longer durations linked to worse cardiovascular, metabolic, and cognitive outcomes. Shown as a general reference point, not a personalized target \u{2014} the indicator below still compares tonight against your own recent range."

    private var sriTooltip: String {
        "Sleep Regularity Index (Phillips et al., 2017, Scientific Reports) measures how similar your sleep schedule is night to night, from -100 (completely different every night) to +100 (identical every night) \u{2014} a different lens from the median/earliest/latest times above, which describe when you sleep rather than how consistent it is. A 2024 UK Biobank study (Windred et al., Sleep) found sleep regularity predicted mortality risk more strongly than sleep duration. Shown here as context, not a target \u{2014} compared only against your own recent history, like everything else in this app."
    }

    @ViewBuilder
    private func timeRegularityGrid(bedtime: SleepRegularity.Summary?, wake: SleepRegularity.Summary?) -> some View {
        if bedtime == nil && wake == nil {
            Text("Not enough nights yet")
                .emptyStateCaptionStyle()
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
                Text(label).statLabelStyle()
                Text(Self.timeFormatter.string(from: value)).statValueStyle()
                if let range {
                    Text("\(Self.timeFormatter.string(from: range.earliest))\u{2013}\(Self.timeFormatter.string(from: range.latest))")
                        .supportingTextStyle()
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

        if let lastNight = month.last {
            lastNightBedStart = lastNight.bedStart
            lastNightWakeEnd = lastNight.wakeEnd

            if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: lastNight.date) {
                afterWorkout = (await workouts).contains {
                    Calendar.current.isDate($0.startDate, inSameDayAs: yesterday) && $0.duration >= 45 * 60
                }
            }
        }

        SectionLoadCoordinator.shared.markLoaded("Rest")
    }
}
