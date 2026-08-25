import SwiftUI
import HealthKit
import UIKit

struct HeartSection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @State private var restingHR: Double?
    @State private var hrv: Double?
    @State private var vo2Max: Double?
    @State private var walkingHR: Double?
    @State private var hrRecovery: Double?
    @State private var walkingSpeed: Double?
    @State private var restingHRRange: (low: Double, high: Double)?
    @State private var hrvRange: (low: Double, high: Double)?
    @State private var walkingHRRange: (low: Double, high: Double)?
    @State private var hrRecoveryRange: (low: Double, high: Double)?
    @State private var walkingSpeedRange: (low: Double, high: Double)?
    @State private var vo2MaxTrend: [(date: Date, value: Double)] = []
    @State private var maxHRResult: MaxHeartRateEngine.Result?
    @State private var zones: HeartRateZoneEngine.ZoneBreakdown?
    @State private var weekZones: HeartRateZoneEngine.ZoneBreakdown?
    @State private var monthZones: HeartRateZoneEngine.ZoneBreakdown?
    @State private var manualMaxHRText = ""
    @FocusState private var isManualHRFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: LifeArea.heart.systemImage)
                    .foregroundStyle(LifeArea.heart.tint)
                Text("Heart & Vitals").font(.title3.weight(.semibold))
                Spacer()
                Text("Today").statLabelStyle()
            }

            Text(restingHR.map { "\(NumberFormat.int($0)) bpm resting" } ?? "No data yet")
                .headlineValueStyle()

            if let restingHR, let range = restingHRRange {
                LowHighIndicator(value: restingHR, low: range.low, high: range.high, label: "Resting heart rate")
            }

            if hrv == nil && hrRecovery == nil && walkingHR == nil && walkingSpeed == nil && vo2Max == nil && vo2MaxTrend.count < 2 {
                Text("HRV compared only to your own history \u{2014} no fixed target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                hrvRecoveryGrid
                walkingGrid

                if vo2Max != nil || vo2MaxTrend.count >= 2 {
                    Divider()
                    vo2MaxSection
                }
            }

            if let zones, let maxHR = maxHRResult {
                Divider()
                zoneSection(scopeLabel: "Today", zones: zones, maxHR: maxHR, showTooltip: true)
            }
            if let weekZones, let maxHR = maxHRResult {
                Divider()
                zoneSection(scopeLabel: "This week", zones: weekZones, maxHR: maxHR)
            }
            if let monthZones, let maxHR = maxHRResult {
                Divider()
                zoneSection(scopeLabel: "This month", zones: monthZones, maxHR: maxHR)
            }

            manualOverrideRow
        }
        .task { await refresh() }
    }

    /// General education only — what HRV is and what it predicts across
    /// people in general, never a claim about what today's specific
    /// number means for this person (see `hrvRange`'s own-history-only
    /// framing above, and the fallback message when no wearable is
    /// present).
    private static let hrvTooltip = "Heart rate variability is the tiny variation in time between heartbeats, reflecting the balance between your sympathetic and parasympathetic nervous systems. Reduced HRV was first linked to higher mortality in patients recovering from heart attacks (Kleiger et al., 1987), and it's since become a widely used marker of stress, recovery, and autonomic health generally. Absolute values vary enormously between people by age, genetics, and fitness, which is exactly why it's only meaningful against your own history \u{2014} never against someone else's number or a population target."

    /// Same general-education-only framing as `hrvTooltip` \u{2014} what
    /// VO2 max means and predicts in general, not a verdict on this
    /// person's number.
    private static let vo2MaxTooltip = "VO2 max measures how efficiently your body uses oxygen during intense exercise \u{2014} the standard measure of cardiorespiratory fitness. A 2018 study of 122,000+ adults (Mandsager et al., JAMA Network Open) found low fitness carried a higher mortality risk than smoking, diabetes, or heart disease, with no ceiling \u{2014} the fittest had the lowest risk of anyone measured. Shown here as a wearable estimate from your walking and running workouts, not a lab treadmill test \u{2014} directionally useful, not clinically precise."

    /// Same general-education-only framing again. Walking speed is the
    /// one metric in this grid that needs no wearable at all — it's
    /// measured by the iPhone itself during ordinary walks — which is
    /// why it's included in the "any data at all" check below even
    /// though the others here typically need a Watch.
    private static let walkingSpeedTooltip = "Walking speed reflects overall physiological reserve \u{2014} your cardiovascular, muscular, and neurological systems all have to work together to move efficiently. A pooled analysis of 9 studies and over 34,000 older adults (Studenski et al., 2011, JAMA) found gait speed alone predicted survival about as well as combining age, sex, and chronic health conditions. Measured passively by your iPhone during ordinary walks, not a formal assessment — and like HRV, absolute values vary by age and leg length, so it's shown here only against your own recent pattern."

    private static let kmPerHour = HKUnit.meterUnit(with: .kilo).unitDivided(by: .hour())

    private var twoColumns: [GridItem] {
        [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    }

    private var hrvRecoveryGrid: some View {
        LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 10) {
            if let hrv {
                statCell("HRV (overnight)", "\(NumberFormat.int(hrv)) ms", value: hrv, range: hrvRange, tooltip: Self.hrvTooltip)
            }
            if let hrRecovery {
                statCell("Recovery", "\(NumberFormat.int(hrRecovery)) bpm", value: hrRecovery, range: hrRecoveryRange)
            }
        }
    }

    private var walkingGrid: some View {
        LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 10) {
            if let walkingSpeed {
                statCell("Walking speed", "\(NumberFormat.decimal1(walkingSpeed)) km/h", value: walkingSpeed, range: walkingSpeedRange, tooltip: Self.walkingSpeedTooltip)
            }
            if let walkingHR {
                statCell("Walking HR", "\(NumberFormat.int(walkingHR)) bpm", value: walkingHR, range: walkingHRRange)
            }
        }
    }

    /// VO2 max's current value and its trend used to live in two places
    /// (a stat-grid cell here, and the trend's own "\u{2192}" range line) \u{2014}
    /// stating the same number twice a few lines apart. Merged into one
    /// block instead: the current value shown once, at more weight than
    /// an ordinary stat cell since VO2 max moves slowly enough that the
    /// trend below it is where any real change actually becomes visible.
    private var vo2MaxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Text("VO2 max").statLabelStyle()
                InfoTooltip(text: Self.vo2MaxTooltip)
                Spacer()
                Text("Past 3 months").statLabelStyle()
            }
            if let vo2Max {
                Text("\(NumberFormat.decimal1(vo2Max)) mL/kg/min").headlineValueStyle()
            }
            if vo2MaxTrend.count >= 2 {
                TrendChart(points: vo2MaxTrend)
                if let first = vo2MaxTrend.first, let last = vo2MaxTrend.last {
                    Text("\(NumberFormat.decimal1(first.value)) \u{2192} \(NumberFormat.decimal1(last.value)) mL/kg/min")
                        .supportingTextStyle()
                }
            }
        }
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

    private func zoneSection(scopeLabel: String, zones: HeartRateZoneEngine.ZoneBreakdown, maxHR: MaxHeartRateEngine.Result, showTooltip: Bool = false) -> some View {
        let bounds = restingHR.map { HeartRateZoneEngine.zoneBoundaries(restingHR: $0, maxHR: maxHR.value) } ?? []
        let appleZone2Low = Int(maxHR.value * 0.6)
        let appleZone2High = Int(maxHR.value * 0.7)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 2) {
                    Text("Heart rate zones").statLabelStyle()
                    if showTooltip {
                        InfoTooltip(text: "Zone 2 means easy, conversational effort \u{2014} roughly 60\u{2013}70% of heart rate reserve, using the Karvonen method (the gap between resting and max heart rate, not max alone). Computed from your resting heart rate and max heart rate (\(NumberFormat.int(maxHR.value)) bpm, \(sourceLabel(maxHR.source))). Apple's Fitness app instead uses 60\u{2013}70% of max heart rate directly, no resting heart rate factored in \u{2014} placing Zone 2 at \(appleZone2Low)\u{2013}\(appleZone2High) bpm. Neither is wrong, just different conventions. All windows here (today, week, month) use cardio workouts only \u{2014} running, walking, cycling, swimming, hiking, elliptical, rowing, HIIT \u{2014} not overall daily heart rate.")
                    }
                }
                Spacer()
                Text(scopeLabel).statLabelStyle()
            }

            if zones.driftingIntoMiddle {
                Text("More time landed in the moderate middle zone than in the easy zones \u{2014} a common way to drift out of true Zone 2 without noticing.")
                    .supportingTextStyle()
            }

            HStack(spacing: 0) {
                zoneLabel("Z1", zones.zone1Minutes, range: zoneRangeLabel(0, bounds: bounds))
                zoneDivider
                zoneLabel("Z2", zones.zone2Minutes, range: zoneRangeLabel(1, bounds: bounds), isFeatured: true)
                zoneDivider
                zoneLabel("Z3", zones.zone3Minutes, range: zoneRangeLabel(2, bounds: bounds))
                zoneDivider
                zoneLabel("Z4", zones.zone4Minutes, range: zoneRangeLabel(3, bounds: bounds))
                zoneDivider
                zoneLabel("Z5", zones.zone5Minutes, range: zoneRangeLabel(4, bounds: bounds))
            }
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var zoneDivider: some View {
        Divider().frame(height: 34)
    }

    /// Zone 1's floor is resting HR itself, not a meaningful lower
    /// bound to show, so it's displayed as "under X" instead — and Zone
    /// 5's ceiling (120% of reserve) can exceed max HR by construction,
    /// so it's shown open-ended rather than as a real upper limit.
    private func zoneRangeLabel(_ index: Int, bounds: [ClosedRange<Double>]) -> String {
        guard bounds.indices.contains(index) else { return "" }
        let range = bounds[index]
        if index == 0 { return "<\(Int(range.upperBound))" }
        if index == bounds.count - 1 { return "\(Int(range.lowerBound))+" }
        return "\(Int(range.lowerBound))\u{2013}\(Int(range.upperBound))"
    }

    private func zoneLabel(_ name: String, _ minutes: Double, range: String, isFeatured: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(isFeatured ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(isFeatured ? .primary : .secondary)
            Text("\(Int(minutes))")
                .font(isFeatured ? .subheadline.weight(.semibold) : .caption)
                .foregroundStyle(isFeatured ? .primary : .secondary)
            if !range.isEmpty {
                Text(range).supportingTextStyle()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The three-source priority this describes (manual, observed
    /// workouts, formula) mirrors `MaxHeartRateEngine.resolve` exactly \u{2014}
    /// keep this in sync if that logic changes.
    private static let maxHRTooltip = "Max HR comes from one of three sources, in priority order: a number you enter manually, the top 5% of your own workout heart-rate readings (used only if within 10 bpm of the age-based estimate, to rule out a sensor glitch), or the age-based formula alone: 206.9 \u{2212} (0.67 \u{00D7} age) \u{2014} Tanaka, Monahan & Seals, 2001, Journal of the American College of Cardiology, a meta-analysis of 351 studies and 18,000+ people, found to predict more accurately across the adult age range than the older \u{201C}220 minus age\u{201D} rule."

    /// Reads Dynamic Type on every access (an instance property, not a
    /// cached `static let`) via `dynamicTypeSize`, so a text-size change
    /// while the app is already running — no relaunch needed — is
    /// picked up the same way every other font in this app already
    /// rescales, instead of staying pinned to whatever size was current
    /// the first time this field was measured.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Fixed to the placeholder's own natural width — "Manual override"
    /// is wider than any real value this field will ever hold (even
    /// "220 bpm"), so reserving exactly that much keeps the field's
    /// width constant whether it's empty, mid-typing, or showing the
    /// "bpm" suffix, instead of visibly growing the moment "bpm" appears.
    private var manualOverrideFieldWidth: CGFloat {
        _ = dynamicTypeSize
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        return ceil(("Manual override" as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Pinned alongside the width so the box can't grow vertically
    /// either — a `TextField` mid-edit can report a taller ideal size
    /// than the same field at rest, and this removes any dependence on
    /// that being well-behaved.
    private var manualOverrideFieldHeight: CGFloat {
        _ = dynamicTypeSize
        return ceil(UIFont.preferredFont(forTextStyle: .subheadline).lineHeight)
    }

    private var manualOverrideRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text("Max HR: \(maxHRResult.map { "\(NumberFormat.int($0.value)) bpm (\(sourceLabel($0.source)))" } ?? "\u{2014}")")
                    .supportingTextStyle()
                InfoTooltip(text: Self.maxHRTooltip)
            }
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    TextField("Manual override", text: $manualMaxHRText, prompt: Text("Manual override").font(.subheadline).foregroundStyle(.secondary))
                        .font(.subheadline)
                        .fixedSize(horizontal: true, vertical: false)
                        .keyboardType(.numberPad)
                        .focused($isManualHRFieldFocused)
                        .onSubmit { submitManualHR() }
                        .onChange(of: isManualHRFieldFocused) { _, isFocused in
                            if !isFocused { submitManualHR() }
                        }
                    if !manualMaxHRText.isEmpty {
                        Text("bpm").supportingTextStyle()
                    }
                }
                .frame(width: manualOverrideFieldWidth, height: manualOverrideFieldHeight, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isManualHRFieldFocused ? Color.accentColor : Color.secondary.opacity(0.3))
                )
                if !manualMaxHRText.isEmpty {
                    Button {
                        manualMaxHRText = ""
                        ManualMaxHeartRateStore.value = nil
                        isManualHRFieldFocused = false
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func submitManualHR() {
        if let value = Double(manualMaxHRText) {
            ManualMaxHeartRateStore.value = value
        } else if manualMaxHRText.isEmpty {
            ManualMaxHeartRateStore.value = nil
        }
        Task { await refresh() }
    }

    /// Low/high bounds from whatever days of history are actually
    /// available in the window — as few as zero. With zero or one valid
    /// day there's nothing to compare against, so the caller falls back
    /// to the current value as both bounds, which centers the dot. With
    /// enough days to spare one from each end, the single most extreme
    /// day is dropped before taking the bounds — at a 7-day window, a
    /// percentage-based trim (5th/95th percentile) rounds down to zero
    /// effective trim, so a lone unusually good or bad day would
    /// otherwise stretch the scale so far that every ordinary day,
    /// including today, reads as bunched at one end.
    private static func minMax(_ history: [Double]) -> (low: Double, high: Double)? {
        let positive = history.filter { $0 > 0 }.sorted()
        guard !positive.isEmpty else { return nil }
        if positive.count >= 5 {
            return (positive[1], positive[positive.count - 2])
        }
        return (positive.first!, positive.last!)
    }

    /// One average per night, from whichever nights have both a
    /// bedtime and wake time recorded and at least one HRV sample
    /// falling inside that window — daytime readings (noisier, less
    /// representative of autonomic recovery than sleeping HRV) are
    /// excluded rather than blended in.
    private static func overnightHRVAverages(nights: [HealthKitManager.SleepNightSummary],
                                              samples: [(date: Date, ms: Double)]) -> [Double] {
        nights.compactMap { night -> Double? in
            guard let bedStart = night.bedStart, let wakeEnd = night.wakeEnd else { return nil }
            let overnight = samples.filter { $0.date >= bedStart && $0.date <= wakeEnd }
            guard !overnight.isEmpty else { return nil }
            return overnight.reduce(0.0) { $0 + $1.ms } / Double(overnight.count)
        }
    }

    /// Sums per-zone minutes across several workouts' breakdowns.
    /// Deliberately not one `breakdown()` call over all their
    /// concatenated samples — the engine fills the gap between
    /// consecutive samples (capped at 2 minutes), so the boundary
    /// between two unrelated workouts would otherwise get miscounted as
    /// a couple of minutes of continuous effort.
    private static func sumZones(_ breakdowns: [HeartRateZoneEngine.ZoneBreakdown]) -> HeartRateZoneEngine.ZoneBreakdown {
        HeartRateZoneEngine.ZoneBreakdown(
            zone1Minutes: breakdowns.reduce(0) { $0 + $1.zone1Minutes },
            zone2Minutes: breakdowns.reduce(0) { $0 + $1.zone2Minutes },
            zone3Minutes: breakdowns.reduce(0) { $0 + $1.zone3Minutes },
            zone4Minutes: breakdowns.reduce(0) { $0 + $1.zone4Minutes },
            zone5Minutes: breakdowns.reduce(0) { $0 + $1.zone5Minutes }
        )
    }

    private func sourceLabel(_ source: MaxHeartRateEngine.Source) -> String {
        switch source {
        case .observed: return "from your workouts"
        case .formula: return "estimated from age"
        case .manual: return "manual"
        }
    }

    private func refresh() async {
        async let rhr = healthKit.fetchTodayValue(for: .restingHeartRate)
        async let vo2MaxVal = healthKit.fetchTodayValue(for: .vo2Max)
        async let walkingHRVal = healthKit.fetchTodayValue(for: .walkingHeartRateAverage)
        async let hrRecoveryVal = healthKit.fetchTodayValue(for: .heartRateRecovery)
        async let history = healthKit.fetchDailyTotals(
            for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 28, option: .discreteAverage)
        async let weekNights = healthKit.fetchSleepNights(days: 7)
        async let hrvSamples = healthKit.fetchHRVSamples(days: 8)
        async let walkingHRHistory = healthKit.fetchDailyTotals(
            for: .walkingHeartRateAverage, unit: HKUnit.count().unitDivided(by: .minute()), days: 7, option: .discreteAverage)
        async let hrRecoveryHistory = healthKit.fetchDailyTotals(
            for: .heartRateRecoveryOneMinute, unit: HKUnit.count().unitDivided(by: .minute()), days: 7, option: .discreteAverage)
        async let walkingSpeedVal = healthKit.fetchTodayTotal(for: .walkingSpeed, unit: Self.kmPerHour, option: .discreteAverage)
        async let walkingSpeedHistory = healthKit.fetchDailyTotals(
            for: .walkingSpeed, unit: Self.kmPerHour, days: 7, option: .discreteAverage)
        async let vo2MaxSamples = healthKit.fetchVO2MaxSamples(days: 91)
        // One 90-day workout fetch, filtered down in-memory for the
        // 28-day figures below, instead of a second, overlapping
        // `fetchWorkouts(daysBack: 28)` query.
        async let ninetyDayWorkouts = healthKit.fetchWorkouts(daysBack: 90)

        restingHR = await rhr
        vo2Max = await vo2MaxVal
        walkingHR = await walkingHRVal
        vo2MaxTrend = await vo2MaxSamples
        hrRecovery = await hrRecoveryVal
        walkingSpeed = await walkingSpeedVal
        walkingSpeedRange = Self.minMax(await walkingSpeedHistory)

        let nightlyHRV = Self.overnightHRVAverages(nights: await weekNights, samples: await hrvSamples)
        hrv = nightlyHRV.last
        hrvRange = Self.minMax(nightlyHRV)

        let positiveHistory = (await history).filter { $0 > 0 }.sorted()
        if positiveHistory.count >= 5 {
            let lowIndex = Int(Double(positiveHistory.count) * 0.05)
            let highIndex = min(positiveHistory.count - 1, Int(Double(positiveHistory.count) * 0.95))
            restingHRRange = (positiveHistory[lowIndex], positiveHistory[highIndex])
        }

        walkingHRRange = Self.minMax(await walkingHRHistory)
        hrRecoveryRange = Self.minMax(await hrRecoveryHistory)

        let age = healthKit.fetchAge()
        // One per-workout heart-rate fetch, covering the full 90 days,
        // feeds both `MaxHeartRateEngine` (which wants observed samples
        // across every workout type, not just cardio) and the
        // month/week/today cardio zone breakdowns below — rather than
        // querying each workout's heart-rate samples a second time for
        // the 28-day cardio subset.
        let allWorkouts = await ninetyDayWorkouts
        let samplesById = await healthKit.fetchHeartRateSamples(for: allWorkouts)
        let observedSamples = samplesById.values.flatMap { $0.map(\.bpm) }
        let result = MaxHeartRateEngine.resolve(
            observedWorkoutSamples: observedSamples,
            age: age,
            manualOverride: ManualMaxHeartRateStore.value
        )
        maxHRResult = result
        if let stored = ManualMaxHeartRateStore.value {
            manualMaxHRText = "\(Int(stored))"
        }

        let monthCutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let allMonthWorkouts = allWorkouts.filter { $0.startDate >= monthCutoff }
        let cardioMonthWorkouts = allMonthWorkouts.filter(\.isCardio)
        let weekCutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cardioWeekWorkouts = cardioMonthWorkouts.filter { $0.startDate >= weekCutoff }
        let cardioTodayWorkouts = cardioMonthWorkouts.filter { Calendar.current.isDateInToday($0.startDate) }
        let cardioSamplesById = samplesById

        if let restingHR {
            // All three windows are cardio-workouts-only now, for a
            // consistent comparison across them — no qualifying
            // workouts still produces a real (all-zero) breakdown
            // rather than nil, so the block reads "0 everywhere"
            // instead of vanishing (`sumZones` over an empty array
            // already reduces to zeros).
            //
            // Breakdown computed once per workout, then summed into
            // each window by filtering — not once per window.
            // `cardioTodayWorkouts`/`cardioWeekWorkouts` are nested
            // subsets of `cardioMonthWorkouts`, so recomputing
            // `breakdown` per window (real per-sample-gap work — see
            // its own doc comment) would redo the same workout's
            // bucketing up to three times over.
            let breakdownsById = Dictionary(uniqueKeysWithValues: cardioMonthWorkouts.map { workout in
                (workout.id, HeartRateZoneEngine.breakdown(samples: cardioSamplesById[workout.id] ?? [], restingHR: restingHR, maxHR: result.value))
            })
            zones = Self.sumZones(cardioTodayWorkouts.compactMap { breakdownsById[$0.id] })
            weekZones = Self.sumZones(cardioWeekWorkouts.compactMap { breakdownsById[$0.id] })
            monthZones = Self.sumZones(cardioMonthWorkouts.compactMap { breakdownsById[$0.id] })
        } else {
            // No resting HR this cycle (transient fetch failure, or data
            // not synced yet) — clear rather than leave a previous
            // cycle's breakdown on screen mislabeled as current.
            zones = nil
            weekZones = nil
            monthZones = nil
        }

        SectionLoadCoordinator.shared.markLoaded("Heart & Vitals")
    }
}
