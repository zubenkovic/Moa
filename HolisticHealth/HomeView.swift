import SwiftUI
import HealthKit
import UIKit

struct HomeView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var ratingStore = HealthRatingStore.shared

    @State private var heroSentence = "Getting to know your rhythm\u{2026}"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(heroSentence)
                    .font(.title2.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                ratingSection

                Divider()
                MovementSection()
                Divider()
                RestSection()
                Divider()
                HeartSection()
                Divider()
                RMRSection()
                Divider()
                RecoverySection()
                Divider()
                ActivityIndexSection()
            }
            .padding()
        }
        // Tap-to-dismiss for the manual max-HR field (and any future text
        // field): `simultaneousGesture` rather than `onTapGesture` so this
        // never intercepts taps meant for buttons underneath it — it just
        // rides along with whatever tap already landed.
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
        .task {
            if !healthKit.isAuthorized {
                await healthKit.requestAuthorization()
            }
            await refreshHero()
        }
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How's your health today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(HealthRating.allCases, id: \.self) { rating in
                    let isSelected = ratingStore.todaysEntry?.rating == rating
                    Button {
                        ratingStore.logToday(rating)
                    } label: {
                        Text(rating.label)
                            .font(.subheadline)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            if let mode = ratingStore.weeklyModeRating() {
                Text("Mostly \u{201C}\(mode.label.lowercased())\u{201D} this week")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The only thing HomeView itself computes — everything else lives
    /// in its own section, fetching independently in parallel.
    private func refreshHero() async {
        async let stepsHistory = healthKit.fetchDailyTotals(for: .stepCount, unit: .count(), days: 28)
        async let sleepNights = healthKit.fetchSleepNights(days: 28)
        async let heartHistory = healthKit.fetchDailyTotals(
            for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 28, option: .discreteAverage)

        let stepsHist = await stepsHistory
        let sleepHist = (await sleepNights).map(\.asleepHours)
        let heartHist = await heartHistory

        let movementTrend = BaselineEngine.trend(dailyValues: stepsHist)
        let sleepTrend = BaselineEngine.trend(dailyValues: sleepHist)
        let heartTrend = BaselineEngine.trend(dailyValues: heartHist)

        heroSentence = BaselineEngine.heroSentence(movement: movementTrend, rest: sleepTrend, heart: heartTrend)
    }
}

#Preview {
    HomeView()
}
