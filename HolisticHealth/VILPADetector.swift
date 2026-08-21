import Foundation

/// Detects brief bursts of vigorous heart rate that happen outside any
/// logged workout — a fast flight of stairs, a rushed uphill walk —
/// the pattern researchers call VILPA (vigorous intermittent lifestyle
/// physical activity). Uses the same zone infrastructure already built
/// for HR zones: "vigorous" here means Zone 4 or above.
enum VILPADetector {
    static func countBursts(samples: [(date: Date, bpm: Double)], workoutRanges: [ClosedRange<Date>],
                             restingHR: Double, maxHR: Double) -> Int {
        let zone4Floor = HeartRateZoneEngine.zoneBoundaries(restingHR: restingHR, maxHR: maxHR)[3].lowerBound

        let vigorousOutsideWorkouts = samples
            .filter { $0.bpm >= zone4Floor }
            .filter { sample in !workoutRanges.contains { $0.contains(sample.date) } }
            .sorted { $0.date < $1.date }

        // Group samples within 3 minutes of each other into one burst,
        // rather than counting every individual elevated sample.
        var burstCount = 0
        var lastBurstDate: Date?
        for sample in vigorousOutsideWorkouts {
            if let last = lastBurstDate, sample.date.timeIntervalSince(last) < 180 {
                continue
            }
            burstCount += 1
            lastBurstDate = sample.date
        }
        return burstCount
    }

    /// Burst counts per day for the last `days` days, ending yesterday,
    /// from a flat list of samples spanning that window — the input
    /// for a Vigorous Moments low/high range.
    static func dailyBurstCounts(samples: [(date: Date, bpm: Double)], workoutRanges: [ClosedRange<Date>],
                                  restingHR: Double, maxHR: Double, days: Int,
                                  calendar: Calendar = .current) -> [Int] {
        let today = calendar.startOfDay(for: Date())
        var byDay: [Date: [(date: Date, bpm: Double)]] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            byDay[day, default: []].append(sample)
        }

        var counts: [Int] = []
        for offset in stride(from: days, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let daySamples = byDay[day] ?? []
            counts.append(countBursts(samples: daySamples, workoutRanges: workoutRanges, restingHR: restingHR, maxHR: maxHR))
        }
        return counts
    }
}
