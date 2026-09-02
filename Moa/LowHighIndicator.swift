import SwiftUI

/// A compact, minimal indicator showing where today's value sits between
/// the person's own recent low and high. Deliberately no color coding —
/// which end is "good" depends on the metric (a low resting heart rate
/// is great, low steps usually isn't) — so position is the only signal,
/// and the caller passes in whichever low/high range already makes sense
/// (typically a 5th–95th percentile range, not true min/max, so one
/// outlier day doesn't stretch the whole scale).
struct LowHighIndicator: View {
    let value: Double
    let low: Double
    let high: Double
    var width: CGFloat = 90
    var dotDiameter: CGFloat = 13
    /// What this value represents (e.g. "Resting heart rate"), read by
    /// VoiceOver ahead of the position summary below. Position is the
    /// only signal this view carries visually (see the no-color-coding
    /// note above) and it isn't echoed anywhere else in text at most call
    /// sites, so without this, VoiceOver users get nothing telling them
    /// where today sits relative to their own recent range.
    var label: String? = nil

    /// Widened to always include `value`, even when the caller's
    /// low/high came from a trimmed range (dropping the single most
    /// extreme day so one outlier can't stretch the whole scale — see
    /// callers). Trimming can exclude today's own reading when today
    /// happens to be that extreme day; without this, such a value would
    /// clamp to the very edge indistinguishably from "always pinned"
    /// instead of legitimately sitting at the edge because it earned it.
    private var effectiveLow: Double { min(low, value) }
    private var effectiveHigh: Double { max(high, value) }

    private var position: Double {
        guard effectiveHigh > effectiveLow else { return 0.5 }
        return (value - effectiveLow) / (effectiveHigh - effectiveLow)
    }

    var body: some View {
        GeometryReader { geometry in
            let midY = geometry.size.height / 2
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: geometry.size.width, height: 3)
                    .position(x: geometry.size.width / 2, y: midY)
                Circle()
                    .fill(Color.primary)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .position(x: geometry.size.width * position, y: midY)
            }
        }
        .frame(width: width, height: max(dotDiameter, 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "Compared to your recent range")
        .accessibilityValue("\(Self.formatted(value)), typical range \(Self.formatted(effectiveLow)) to \(Self.formatted(effectiveHigh))")
    }

    private static func formatted(_ v: Double) -> String {
        v.rounded() == v ? NumberFormat.int(v) : NumberFormat.decimal1(v)
    }
}
