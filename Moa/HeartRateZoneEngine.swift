import Foundation

enum HeartRateZoneEngine {
    struct ZoneBreakdown {
        let zone1Minutes: Double
        let zone2Minutes: Double
        let zone3Minutes: Double
        let zone4Minutes: Double
        let zone5Minutes: Double

        /// True when more time landed in the moderate middle zone than
        /// in the two easy zones combined — the polarized-training
        /// research this app leans on flags that middle ground as the
        /// least effective place to spend time: too hard for real
        /// aerobic-base benefit, not hard enough for a real high-
        /// intensity adaptation.
        var driftingIntoMiddle: Bool {
            zone3Minutes > (zone1Minutes + zone2Minutes)
        }
    }

    /// Karvonen (heart rate reserve) zone boundaries. Zone 2 here means
    /// the popular easy/conversational/fat-oxidation-focused zone —
    /// worth being explicit about, since some sports-science papers use
    /// "Zone 2" for a different, much harder threshold zone.
    static func zoneBoundaries(restingHR: Double, maxHR: Double) -> [ClosedRange<Double>] {
        let reserve = maxHR - restingHR
        func bound(_ fraction: Double) -> Double { restingHR + reserve * fraction }
        return [
            bound(0.0)...bound(0.6),
            bound(0.6)...bound(0.7),
            bound(0.7)...bound(0.8),
            bound(0.8)...bound(0.9),
            bound(0.9)...bound(1.2)
        ]
    }

    /// Buckets timestamped heart rate samples into minutes per zone,
    /// using the gap to the next sample as that sample's duration.
    static func breakdown(samples: [(date: Date, bpm: Double)], restingHR: Double, maxHR: Double) -> ZoneBreakdown {
        let bounds = zoneBoundaries(restingHR: restingHR, maxHR: maxHR)
        var minutes = [Double](repeating: 0, count: 5)
        let sorted = samples.sorted { $0.date < $1.date }

        for i in 0..<sorted.count {
            let duration: Double
            if i + 1 < sorted.count {
                duration = min(sorted[i + 1].date.timeIntervalSince(sorted[i].date), 120) / 60
            } else {
                duration = 0.5
            }
            if let zoneIndex = bounds.firstIndex(where: { $0.contains(sorted[i].bpm) }) {
                minutes[zoneIndex] += duration
            }
        }

        return ZoneBreakdown(zone1Minutes: minutes[0], zone2Minutes: minutes[1], zone3Minutes: minutes[2],
                              zone4Minutes: minutes[3], zone5Minutes: minutes[4])
    }
}
