import SwiftUI
import HealthKit

struct RMRSection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @StateObject private var restingEnergyPreference = RestingEnergyPreferenceStore.shared

    @State private var appleEstimate: Double?
    @State private var katchMcArdleEstimate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Resting energy").font(.title3.weight(.semibold))
                InfoTooltip(text: "Both numbers are estimates, not clinical measurements. Apple's figure comes from a population-average formula based on age, sex, height, and weight \u{2014} it doesn't account for your actual muscle mass. It's shown here as your median over the last 7 completed days rather than today's running total, since that total only accrues through the day and would otherwise look artificially low each morning \u{2014} median rather than mean so one low-coverage day (Watch not worn, charging overnight) doesn't drag the figure down. The Katch-McArdle figure uses real lean-mass data from a smart scale when one's available, usually more accurate for anyone whose muscle mass differs from average \u{2014} but only as reliable as the scale's own reading, which shifts with hydration and other factors. Tap either number to make it the one used for Movement's Total calories.")
            }

            HStack(spacing: 24) {
                estimateButton("Apple estimate", value: appleEstimate, method: .appleEstimate)
                if let katchMcArdleEstimate {
                    estimateButton("Katch-McArdle", value: katchMcArdleEstimate, method: .katchMcArdle)
                }
            }
        }
        .task { await refresh() }
    }

    private func estimateButton(_ label: String, value: Double?, method: RestingEnergyMethod) -> some View {
        let isSelected = restingEnergyPreference.value == method
        return Button {
            restingEnergyPreference.value = method
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline).foregroundStyle(isSelected ? .secondary : .tertiary)
                Text(value.map { "\(Int($0)) kcal" } ?? "\u{2014}")
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func refresh() async {
        // Apple's basal-energy figure accrues linearly through the day,
        // so today's running total only ever reflects a fraction of the
        // real value until the day ends — averaging the last 7 completed
        // days (`fetchDailyTotals` already excludes today) gives a
        // stable full-day estimate that's actually comparable to
        // Katch-McArdle's static one.
        async let appleHistory = healthKit.fetchDailyTotals(for: .basalEnergyBurned, unit: .kilocalorie(), days: 7)
        async let leanMass = healthKit.fetchLatestSample(for: .leanBodyMass, unit: .gramUnit(with: .kilo))

        let positiveHistory = (await appleHistory).filter { $0 > 0 }
        appleEstimate = RMREngine.median(positiveHistory)
        if let mass = await leanMass {
            katchMcArdleEstimate = RMREngine.katchMcArdle(leanBodyMassKg: mass)
        }
    }
}
