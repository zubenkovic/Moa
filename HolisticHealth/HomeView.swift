import SwiftUI
import HealthKit
import UIKit

struct HomeView: View {
    @StateObject private var healthKit = HealthKitManager.shared
    @StateObject private var ratingStore = HealthRatingStore.shared
    @StateObject private var loadCoordinator = SectionLoadCoordinator.shared

    @State private var heroSentence = "Learning your rhythm\u{2026}"
    @State private var isRefreshing = false
    // Latches true the first time every section has reported in via
    // `loadCoordinator` and stays true — later manual refreshes update
    // content in place (see `refreshButton`'s own spinner) rather than
    // hiding the screen again.
    @State private var hasLoadedOnce = false
    // Changing this remounts every section below, which is how they're
    // made to refetch on demand — each one fetches independently via
    // its own `.task` and has no refresh method of its own to call.
    @State private var refreshID = UUID()

    /// The names each section below reports to `SectionLoadCoordinator`
    /// via `markLoaded(_:)`, at the end of its own `refresh()` — kept as
    /// one list here, next to where the sections themselves are mounted,
    /// rather than a count living in `SectionLoadCoordinator` with
    /// nothing tying it to the actual set of views below.
    private static let sectionNames = [
        "Movement", "Rest", "Heart & Vitals", "Resting energy", "Recovery", "Activity Index"
    ]

    var body: some View {
        // A NavigationStack is what gives this screen the native
        // scroll-edge material behind the status bar/Dynamic Island (the
        // same mechanism Apple Fitness, Music, and Settings use): the bar
        // starts fully transparent and gains a blur + hairline only once
        // content actually scrolls beneath it, all handled by the system
        // rather than a hand-rolled GeometryReader + safe-area overlay.
        // The title itself is `heroSentence` rather than the app's own
        // name — see `BaselineEngine.heroSentence` for why, and for the
        // no-trailing-period convention every variant of it follows.
        NavigationStack {
            // The ScrollView (and every section inside it) stays mounted
            // and fetching the whole time, even while hidden — that's
            // what lets `loadCoordinator` ever reach `isReady` in the
            // first place. Only its opacity/hit-testing changes; an
            // `if/else` here that unmounted it until ready would mean
            // its sections never start fetching, so `isReady` would
            // never arrive.
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ratingSection.sectionCardStyle()

                        // Kept as a literal name next to each view below,
                        // and mirrored exactly by `Self.sectionNames` —
                        // the single list `SectionLoadCoordinator` is
                        // configured from, so the two can't drift apart
                        // silently the way a hand-maintained count could.
                        MovementSection().sectionCardStyle()
                        RestSection().sectionCardStyle()
                        HeartSection().sectionCardStyle()
                        RMRSection().sectionCardStyle()
                        RecoverySection().sectionCardStyle()
                        ActivityIndexSection().sectionCardStyle()

                        footerLinks
                    }
                    .id(refreshID)
                    .padding()
                }
                .opacity(hasLoadedOnce ? 1 : 0)
                .allowsHitTesting(hasLoadedOnce)

                if !hasLoadedOnce {
                    loadingView
                }
            }
            .animation(.default, value: hasLoadedOnce)
            // Cards use `secondarySystemGroupedBackground`, which is
            // designed to sit on top of `systemGroupedBackground` (the
            // standard Apple "grouped list" pairing — see Settings). Left
            // on the default plain `systemBackground`, that pairing is
            // white on white in light mode: only visible in dark mode,
            // where `systemBackground` is black and the card reads as
            // dark gray.
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            // Tap-to-dismiss for the manual max-HR field (and any future
            // text field): `simultaneousGesture` rather than
            // `onTapGesture` so this never intercepts taps meant for
            // buttons underneath it — it just rides along with whatever
            // tap already landed.
            .simultaneousGesture(
                TapGesture().onEnded {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
            .navigationTitle(heroSentence)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshButton
                }
            }
            .task {
                loadCoordinator.configure(sections: Self.sectionNames)
                if !healthKit.isAuthorized {
                    await healthKit.requestAuthorization()
                }
                await refreshHero()
            }
            .onChange(of: loadCoordinator.isReady) { _, isReady in
                if isReady {
                    hasLoadedOnce = true
                }
            }
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 16) {
            Link("Privacy Policy", destination: URL(string: "https://github.com/zubenkovic/HolisticHealth/blob/main/PRIVACY.md")!)
            Link("View source on GitHub", destination: URL(string: "https://github.com/zubenkovic/HolisticHealth")!)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading your data\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var refreshButton: some View {
        Button {
            Task { await performManualRefresh() }
        } label: {
            if isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(isRefreshing || !hasLoadedOnce)
    }

    /// Re-fetches everything without needing to relaunch the app.
    /// Bumping `refreshID` remounts every section, which re-triggers
    /// their own `.task`-based fetches; `refreshHero` is called
    /// alongside since it's the one thing HomeView itself owns.
    /// `loadCoordinator.reset()` clears the previous cycle's count first.
    /// Stays disabled (`isRefreshing`) until `loadCoordinator.isReady`
    /// actually flips true again for this cycle, not just until
    /// `refreshHero` returns — `refreshHero` is a handful of lightweight
    /// queries for the hero sentence alone, far faster than the six
    /// sections' own heavier fetches, so releasing the button as soon as
    /// it finished used to let a second tap call `reset()` again while
    /// the first cycle's sections were still in flight, corrupting the
    /// coordinator's count with their late, orphaned completions.
    private func performManualRefresh() async {
        isRefreshing = true
        loadCoordinator.reset()
        refreshID = UUID()
        async let heroDone: Void = refreshHero()
        async let sectionsDone: Void = loadCoordinator.waitUntilReady()
        _ = await (heroDone, sectionsDone)
        isRefreshing = false
    }

    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How's your health today?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 5) {
                ForEach(HealthRating.allCases, id: \.self) { rating in
                    let isSelected = ratingStore.todaysEntry?.rating == rating
                    Button {
                        ratingStore.logToday(rating)
                    } label: {
                        Text(rating.label)
                            // Kept to one line at a shrinkable size rather
                            // than wrapping — "Very good" and "Excellent"
                            // are the widest of the five, and the exact
                            // wording of this scale isn't ours to
                            // paraphrase (see HealthRating's doc comment).
                            .font(.footnote)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 2)
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
