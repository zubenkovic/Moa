import SwiftUI
import HealthKit

struct RMRSection: View {
    @StateObject private var healthKit = HealthKitManager.shared

    @StateObject private var restingEnergyPreference = RestingEnergyPreferenceStore.shared

    @State private var appleEstimate: Double?
    @State private var katchMcArdleEstimate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                HStack(spacing: 2) {
                    Text("Resting energy").font(.title3.weight(.semibold))
                    InfoTooltip(text: "Both numbers are estimates, not clinical measurements. Apple's figure comes from a population-average formula (age, sex, height, weight) that doesn't account for your actual muscle mass. Shown as your median over the last 7 completed days rather than today's running total, so it doesn't read artificially low each morning \u{2014} median rather than mean so one low-coverage day doesn't skew it. Katch-McArdle uses real lean-mass data from a smart scale when available, usually more accurate, but only as reliable as that scale's own reading. Tap either number to use it for Movement's Total calories.")
                }
                Spacer()
            }

            // Same two-column, 50/50 grid every other section (Heart &
            // Vitals, Rest, Movement) uses for its stat cells — flexible
            // columns are also what makes this card span full width
            // instead of hugging its own content, matching the rest.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 10) {
                estimateCell("Apple estimate", value: appleEstimate, method: .appleEstimate)
                if let katchMcArdleEstimate {
                    estimateCell("Katch-McArdle", value: katchMcArdleEstimate, method: .katchMcArdle)
                }
            }
        }
        .task { await refresh() }
    }

    private func estimateCell(_ label: String, value: Double?, method: RestingEnergyMethod) -> some View {
        let isSelected = restingEnergyPreference.value == method
        return Button {
            restingEnergyPreference.value = method
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).statLabelStyle()
                Text(value.map { "\(NumberFormat.int($0)) kcal" } ?? "\u{2014}")
                    .font(isSelected ? .headline : .subheadline)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

        SectionLoadCoordinator.shared.markLoaded("Resting energy")
    }
}
