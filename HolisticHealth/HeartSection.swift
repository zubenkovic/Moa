import SwiftUI
import HealthKit

struct HeartSection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @State private var restingHR: Double?
    @State private var hrv: Double?
    @State private var vo2Max: Double?
    @State private var walkingHR: Double?
    @State private var hrRecovery: Double?
    @State private var restingHRRange: (low: Double, high: Double)?
    @State private var hrvRange: (low: Double, high: Double)?
    @State private var walkingHRRange: (low: Double, high: Double)?
    @State private var hrRecoveryRange: (low: Double, high: Double)?
    @State private var vo2MaxRange: (low: Double, high: Double)?
    @State private var maxHRResult: MaxHeartRateEngine.Result?
    @State private var zones: HeartRateZoneEngine.ZoneBreakdown?
    @State private var manualMaxHRText = ""
    @FocusState private var isManualHRFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: LifeArea.heart.systemImage)
                    .foregroundStyle(LifeArea.heart.tint)
                Text("Heart & Vitals").font(.title3.weight(.semibold))
                Spacer()
                Text("Today").font(.subheadline).foregroundStyle(.tertiary)
            }

            Text(restingHR.map { "\(Int($0)) bpm resting" } ?? "No data yet")
                .font(.title.weight(.medium))

            if let restingHR, let range = restingHRRange {
                LowHighIndicator(value: restingHR, low: range.low, high: range.high)
            }

            statGrid

            if let zones, let maxHR = maxHRResult {
                zoneSection(zones: zones, maxHR: maxHR)
            }

            manualOverrideRow
        }
        .task { await refresh() }
    }

    private var statGrid: some View {
        Group {
            if hrv == nil && walkingHR == nil && hrRecovery == nil && vo2Max == nil {
                Text("HRV compared only to your own history \u{2014} no fixed target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                    if let hrv {
                        statCell("HRV (overnight)", "\(Int(hrv)) ms", value: hrv, range: hrvRange)
                    }
                    if let walkingHR {
                        statCell("Walking HR", "\(Int(walkingHR)) bpm", value: walkingHR, range: walkingHRRange)
                    }
                    if let hrRecovery {
                        statCell("Recovery", "\(Int(hrRecovery)) bpm", value: hrRecovery, range: hrRecoveryRange)
                    }
                    if let vo2Max {
                        statCell("VO2 max", String(format: "%.1f", vo2Max), value: vo2Max, range: vo2MaxRange)
                    }
                }
            }
        }
    }

    private func statCell(_ label: String, _ display: String, value: Double, range: (low: Double, high: Double)?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.subheadline).foregroundStyle(.tertiary)
            Text(display).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            LowHighIndicator(value: value, low: range?.low ?? value, high: range?.high ?? value, width: 70, dotDiameter: 9)
        }
    }

    private func zoneSection(zones: HeartRateZoneEngine.ZoneBreakdown, maxHR: MaxHeartRateEngine.Result) -> some View {
        let bounds = restingHR.map { HeartRateZoneEngine.zoneBoundaries(restingHR: $0, maxHR: maxHR.value) } ?? []
        let appleZone2Low = Int(maxHR.value * 0.6)
        let appleZone2High = Int(maxHR.value * 0.7)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Heart rate zones").font(.subheadline).foregroundStyle(.tertiary)
                InfoTooltip(text: "Zone 2 means easy, conversational effort \u{2014} the aerobic-base-building zone, roughly 60\u{2013}70% of your heart rate reserve, using the Karvonen method (percentages applied to the gap between your resting and max heart rate, rather than to max heart rate alone). Computed from your resting heart rate and max heart rate (\(Int(maxHR.value)) bpm, \(sourceLabel(maxHR.source))). Apple's own Fitness app uses a simpler method \u{2014} 60\u{2013}70% of max heart rate directly, with no resting heart rate factored in \u{2014} which would place Zone 2 at \(appleZone2Low)\u{2013}\(appleZone2High) bpm instead. Neither is wrong; they're different, commonly used conventions.")
            }

            if zones.driftingIntoMiddle {
                Text("More time landed in the moderate middle zone than in the easy zones \u{2014} a common way to drift out of true Zone 2 without noticing.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
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
            Text(name).font(.subheadline).foregroundStyle(isFeatured ? .primary : .tertiary)
            Text("\(Int(minutes))").font(.subheadline.weight(isFeatured ? .semibold : .regular)).foregroundStyle(isFeatured ? .primary : .secondary)
            if !range.isEmpty {
                Text(range).font(.subheadline).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var manualOverrideRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Max HR: \(maxHRResult.map { "\(Int($0.value)) bpm (\(sourceLabel($0.source)))" } ?? "\u{2014}")")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                TextField("Manual override", text: $manualMaxHRText)
                    .font(.subheadline)
                    .fixedSize()
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .focused($isManualHRFieldFocused)
                    .onSubmit { submitManualHR() }
                    .onChange(of: isManualHRFieldFocused) { _, isFocused in
                        if !isFocused { submitManualHR() }
                    }
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
        async let vo2MaxHistory = healthKit.fetchDailyTotals(
            for: .vo2Max, unit: HKUnit(from: "mL/kg*min"), days: 7, option: .discreteAverage)
        async let workoutSamples = healthKit.fetchWorkoutHeartRateSamples(daysBack: 90)
        async let todaySamples = healthKit.fetchTodayHeartRateSamples()

        restingHR = await rhr
        vo2Max = await vo2MaxVal
        walkingHR = await walkingHRVal
        hrRecovery = await hrRecoveryVal

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
        vo2MaxRange = Self.minMax(await vo2MaxHistory)

        let age = healthKit.fetchAge()
        let result = MaxHeartRateEngine.resolve(
            observedWorkoutSamples: await workoutSamples,
            age: age,
            manualOverride: ManualMaxHeartRateStore.value
        )
        maxHRResult = result
        if let stored = ManualMaxHeartRateStore.value {
            manualMaxHRText = "\(Int(stored))"
        }

        if let restingHR {
            zones = HeartRateZoneEngine.breakdown(samples: await todaySamples, restingHR: restingHR, maxHR: result.value)
        }
    }
}
