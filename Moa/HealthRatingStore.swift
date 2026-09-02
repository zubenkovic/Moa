import Foundation
import Combine

/// The five-point general self-rated health scale used across decades of
/// epidemiological research (poor / fair / good / very good / excellent).
/// Keeping the exact wording matters: it's what makes it honest to
/// describe this as the same instrument that research is about, rather
/// than a bespoke mood scale that merely looks similar.
enum HealthRating: Int, Codable, CaseIterable {
    case poor = 1, fair, good, veryGood, excellent

    var label: String {
        switch self {
        case .poor:     return "Poor"
        case .fair:     return "Fair"
        case .good:     return "Good"
        case .veryGood: return "Very good"
        case .excellent: return "Excellent"
        }
    }
}

struct HealthRatingEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let rating: HealthRating
}

/// Local, on-device log of daily self-rated health. This lives next to
/// the hero sentence on the home screen, not behind a tap — the whole
/// point is that it costs the person nothing to answer.
@MainActor
final class HealthRatingStore: ObservableObject {
    static let shared = HealthRatingStore()

    private let key = "healthRatings"

    @Published private(set) var entries: [HealthRatingEntry] = []

    init() {
        load()
    }

    /// One rating per day — logging again today replaces today's entry
    /// rather than stacking duplicates. This is a daily rating, not a diary.
    func logToday(_ rating: HealthRating) {
        entries.removeAll { Calendar.current.isDateInToday($0.date) }
        entries.append(HealthRatingEntry(date: Date(), rating: rating))
        save()
    }

    var todaysEntry: HealthRatingEntry? {
        entries.first { Calendar.current.isDateInToday($0.date) }
    }

    /// The most common rating over the last 7 days — the mode, not the
    /// average. These are ordinal labels, not numbers: averaging "good"
    /// and "fair" into 3.5 doesn't mean anything real. Returns nil until
    /// there are at least 3 entries in the window, rather than forcing a
    /// pattern out of thin data.
    func weeklyModeRating() -> HealthRating? {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = entries.filter { $0.date >= weekAgo }
        guard recent.count >= 3 else { return nil }

        let counts = Dictionary(grouping: recent, by: { $0.rating }).mapValues { $0.count }
        return counts.max { $0.value < $1.value }?.key
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HealthRatingEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
