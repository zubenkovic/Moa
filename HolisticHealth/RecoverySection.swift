import SwiftUI
import HealthKit

/// Descriptive only, by design — no injury-risk score, no training
/// go/no-go verdict. HRV and resting heart rate are physiological
/// state, not something anyone directly controls, and the research
/// behind training-load ratios (acute:chronic workload) is genuinely
/// contested. This section hands over the ingredients; the person
/// makes the call.
struct RecoverySection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @State private var hrvTrend: MetricTrend?
    @State private var rhrTrend: MetricTrend?
    @State private var lastNightHours: Double?
    @State private var loadTrend: MetricTrend?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "arrow.clockwise.heart")
                    .foregroundStyle(.purple)
                Text("Recovery").font(.title3.weight(.semibold))
                Spacer()
            }

            Text(synthesis)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                if let hrvTrend {
                    Text("HRV: \(describe(hrvTrend, invert: false))")
                }
                if let rhrTrend {
                    Text("Resting heart rate: \(describe(rhrTrend, invert: true))")
                }
                if let lastNightHours {
                    Text("Last night: \(String(format: "%.1f hrs", lastNightHours))")
                }
                if let loadTrend {
                    HStack(spacing: 4) {
                        Text("This week's training load: \(describe(loadTrend, invert: false))")
                        InfoTooltip(text: "Compares this week's total exercise minutes to your trailing 4-week average. Shown as information only \u{2014} the research behind training-load ratios is genuinely mixed, so this isn't a readiness verdict, just context for your own judgment.")
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .task { await refresh() }
    }

    private var synthesis: String {
        let hrvLow = hrvTrend?.direction == .down
        let rhrHigh = rhrTrend?.direction == .up
        if hrvLow || rhrHigh {
            return "A couple of your usual recovery signals are reading a bit below normal today."
        }
        return "Your usual recovery signals look close to normal."
    }

    /// `invert` flips the phrasing for metrics where "up" isn't
    /// obviously "more" in a good way (a higher resting heart rate
    /// reads differently than more steps) \u2014 phrasing only, no
    /// judgment attached either way.
    private func describe(_ trend: MetricTrend, invert: Bool) -> String {
        switch trend.direction {
        case .steady: return "close to your usual"
        case .up: return "a bit higher than usual"
        case .down: return "a bit lower than usual"
        }
    }

    private func refresh() async {
        async let hrvHistory = healthKit.fetchDailyTotals(
            for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: 28, option: .discreteAverage)
        async let rhrHistory = healthKit.fetchDailyTotals(
            for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 28, option: .discreteAverage)
        async let exerciseHistory = healthKit.fetchDailyTotals(for: .appleExerciseTime, unit: .minute(), days: 28)
        async let sleepSummary = healthKit.fetchTodaySleepSummary()

        hrvTrend = BaselineEngine.trend(dailyValues: await hrvHistory)
        rhrTrend = BaselineEngine.trend(dailyValues: await rhrHistory)
        loadTrend = BaselineEngine.trend(dailyValues: await exerciseHistory)
        lastNightHours = (await sleepSummary)?.asleepHours
    }
}
