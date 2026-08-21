import SwiftUI

/// Same filled/empty-dot language as WeeklyDotStrip, arranged as a
/// 7-column grid instead of one long row, so 28 days of daily flags
/// stay compact and scannable rather than a single very wide strip.
struct MonthlyDotGrid: View {
    let activeDays: [Bool]

    private let columns = 7
    private let dotSize: CGFloat = 6
    private let spacing: CGFloat = 5

    var body: some View {
        let rows = (activeDays.count + columns - 1) / columns
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        Circle()
                            .fill(index < activeDays.count && activeDays[index] ? Color.primary : Color.secondary.opacity(0.2))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
    }
}
