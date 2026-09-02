import Foundation

/// Turns a set of bed or wake times into a median "usual" time plus the
/// earliest/latest extremes. Clock times can't be averaged or sorted
/// naively once they cross midnight — 11pm and 1am aren't meaningfully
/// "22 hours apart" the way a raw 24-hour clock would suggest — so every
/// time is first mapped onto a continuous number line anchored at 6pm
/// the previous day, sorted and measured there, then mapped back to a
/// real clock time only for display.
enum SleepRegularity {
    struct Summary {
        let median: Date
        let earliest: Date
        let latest: Date
    }

    static func summarize(times: [Date], calendar: Calendar = .current) -> Summary? {
        guard !times.isEmpty else { return nil }

        let anchored: [(offset: Double, original: Date)] = times.map { time in
            let dayStart = calendar.startOfDay(for: time)
            let sixPM = calendar.date(byAdding: .hour, value: 18, to: dayStart) ?? time
            var offset = time.timeIntervalSince(sixPM)
            // Anything before 6pm belongs to a night that started the
            // previous evening — push it forward a full day on the
            // number line so, e.g., 11pm and 1am land close together
            // instead of far apart.
            if offset < 0 { offset += 24 * 3600 }
            return (offset, time)
        }.sorted { $0.offset < $1.offset }

        let medianOffset = anchored[anchored.count / 2].offset
        let referenceDay = calendar.startOfDay(for: anchored[0].original)
        let sixPM = calendar.date(byAdding: .hour, value: 18, to: referenceDay) ?? referenceDay
        let median = sixPM.addingTimeInterval(medianOffset)

        return Summary(median: median, earliest: anchored.first!.original, latest: anchored.last!.original)
    }

    /// Minutes between two clock times, ignoring which calendar days
    /// they actually fall on — e.g. 11:05pm last Tuesday vs 11:20pm
    /// last night is "15 minutes," not "6 days and 15 minutes." Both
    /// times are mapped onto the same 6pm-anchored number line used by
    /// `summarize`, then compared modulo 24 hours so the wraparound
    /// (e.g. 12:58am vs 12:59am) stays a 1-minute difference either way.
    static func minutesApart(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Double {
        func offset(_ time: Date) -> Double {
            let dayStart = calendar.startOfDay(for: time)
            let sixPM = calendar.date(byAdding: .hour, value: 18, to: dayStart) ?? time
            var value = time.timeIntervalSince(sixPM)
            if value < 0 { value += 24 * 3600 }
            return value
        }

        let daySeconds = 24 * 3600.0
        let diff = abs(offset(a) - offset(b)).truncatingRemainder(dividingBy: daySeconds)
        return min(diff, daySeconds - diff) / 60
    }
}
