import Combine
import SwiftUI

/// Tracks how many of `HomeView`'s independently-fetching section cards
/// have finished their first load, so the screen can wait for all of
/// them before revealing anything — avoiding the "No data yet" flash
/// each card would otherwise show individually while its own fetch is
/// still in flight (the same effect Apple Fitness's own loading screen
/// avoids). Each section calls `markLoaded(_:)` once, with its own name,
/// at the end of its own `refresh()`.
@MainActor
final class SectionLoadCoordinator: ObservableObject {
    static let shared = SectionLoadCoordinator()

    /// The exact set of sections `HomeView` currently mounts, seeded
    /// once via `configure(sections:)` from the same place the section
    /// views themselves are listed — rather than a hand-maintained count
    /// living in this file, disconnected from the list it's meant to
    /// match. `markLoaded` asserts any name it's called with is actually
    /// in this set, so adding a new section and forgetting to add its
    /// name here fails loudly in debug builds instead of silently
    /// leaving `isReady` flip early.
    private var expectedSections: Set<String> = []
    private var loadedSections: Set<String> = []

    @Published private(set) var isReady = false

    private init() {}

    /// Called once, before the first fetch cycle starts.
    func configure(sections: [String]) {
        expectedSections = Set(sections)
        assert(expectedSections.count == sections.count, "SectionLoadCoordinator.configure received a duplicate section name")
    }

    /// Called before starting a new fetch cycle (first launch or manual
    /// refresh) so a stale count left over from the previous cycle can't
    /// make `isReady` flip early.
    func reset() {
        loadedSections.removeAll()
        isReady = false
    }

    func markLoaded(_ section: String) {
        assert(expectedSections.contains(section), "SectionLoadCoordinator.markLoaded(\"\(section)\") — this name isn't in the set passed to configure(sections:); add it there")
        loadedSections.insert(section)
        if loadedSections.isSuperset(of: expectedSections) {
            isReady = true
        }
    }

    /// Suspends until the current cycle's `isReady` flips true. Lets a
    /// caller (the manual refresh button) keep itself disabled for the
    /// whole cycle instead of releasing early — see `HomeView.performManualRefresh`,
    /// which used to re-enable the button as soon as its own unrelated
    /// hero-sentence fetch finished, well before the sections it had
    /// just `reset()` had reported back in. A second tap in that window
    /// called `reset()` again mid-cycle, corrupting `loadedSections` with
    /// stale completions from the orphaned first cycle.
    func waitUntilReady() async {
        for await ready in $isReady.values where ready {
            return
        }
    }
}
