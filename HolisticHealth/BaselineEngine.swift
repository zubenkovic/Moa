import Foundation

enum TrendDirection {
    case up, down, steady
}

struct MetricTrend {
    let recentAverage: Double
    let baselineAverage: Double
    let direction: TrendDirection
    let magnitude: Double  // relative deviation, e.g. 0.15 = 15% away from baseline
}

/// Turns raw daily histories into the plain-language hero sentence.
/// Deliberately has zero HealthKit imports — this is pure logic over
/// arrays of numbers, which makes it easy to unit test and easy to
/// reason about independent of how the data was fetched.
enum BaselineEngine {

    /// Compares a person's most recent 7 days against a slower-moving
    /// ~28-day baseline — two speeds of the same average. A 3-day window
    /// was considered and rejected: it's short enough to be skewed by
    /// ordinary weekday/weekend rhythm rather than a genuine shift.
    ///
    /// `dailyValues` should already exclude today — an in-progress day
    /// compared against a full-day baseline reads as a false deficit
    /// (the exact Apple Watch ring problem), so today is deliberately
    /// left out upstream rather than guarded against here.
    static func trend(dailyValues: [Double]) -> MetricTrend? {
        let values = dailyValues.filter { $0 > 0 }
        guard values.count >= 7 else { return nil }  // not enough history yet

        let recent = Array(values.suffix(7))
        let baselineWindow = Array(values.suffix(min(28, values.count)))
        let recentAverage = recent.reduce(0, +) / Double(recent.count)
        let baselineAverage = baselineWindow.reduce(0, +) / Double(baselineWindow.count)
        guard baselineAverage > 0 else { return nil }

        let ratio = (recentAverage - baselineAverage) / baselineAverage
        // ±8% is a starting threshold, not a scientific constant — tune
        // this against real usage once there's data to look at.
        let direction: TrendDirection = ratio > 0.08 ? .up : (ratio < -0.08 ? .down : .steady)

        return MetricTrend(recentAverage: recentAverage, baselineAverage: baselineAverage,
                            direction: direction, magnitude: abs(ratio))
    }

    /// Builds the one hero sentence from up to three area trends. Rather
    /// than mention every area at once (which starts to read like a
    /// report), it surfaces whichever single area moved the most —
    /// the most notable thing worth saying today.
    static func heroSentence(movement: MetricTrend?, rest: MetricTrend?, heart: MetricTrend?) -> String {
        let candidates: [(LifeArea, MetricTrend)] = [
            movement.map { (LifeArea.movement, $0) },
            rest.map { (LifeArea.sleep, $0) },
            heart.map { (LifeArea.heart, $0) }
        ].compactMap { $0 }

        guard !candidates.isEmpty else {
            return "Learning your rhythm"
        }

        let notable = candidates
            .filter { $0.1.direction != .steady }
            .sorted { $0.1.magnitude > $1.1.magnitude }

        guard let leading = notable.first else {
            return "Same as usual"
        }

        return clause(for: leading.0, direction: leading.1.direction)
    }

    /// Short status fragments, not full sentences — this doubles as the
    /// nav bar title (see `HomeView`), which measured out to roughly a
    /// 32-character single-line budget alongside the toolbar's refresh
    /// button before truncating. No trailing period, same as any other
    /// nav title ("Settings", "Photos").
    private static func clause(for area: LifeArea, direction: TrendDirection) -> String {
        switch (area, direction) {
        case (.movement, .up):   return "More active"
        case (.movement, .down): return "Quieter"
        case (.sleep, .up):      return "Sleeping more"
        case (.sleep, .down):    return "Sleeping less"
        case (.heart, .up):      return "Higher heart rate"
        case (.heart, .down):    return "Lower heart rate"
        case (_, .steady):       return "Same as usual"
        }
    }
}
