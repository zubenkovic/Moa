import SwiftUI

/// Seven dots, oldest to newest, filled for an active day. Deliberately
/// not a streak counter — a missed day just sits there unfilled, no red,
/// no "streak broken" language. Matches the weekend-warrior research
/// this app leans on: the week's overall pattern is what matters, not
/// an unbroken chain of identical days.
struct WeeklyDotStrip: View {
    let activeDays: [Bool]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(activeDays.indices, id: \.self) { index in
                Circle()
                    .fill(activeDays[index] ? Color.primary : Color.secondary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
