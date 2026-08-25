import SwiftUI
import Charts

/// A bare sparkline — just the line shape, no axis, no gridlines, no
/// labels baked into the graphic itself. Matches how every other visual
/// in this app works (`LowHighIndicator`): the shape carries the
/// impression, the actual numbers are stated separately in plain text
/// next to it, rather than the chart trying to be self-explanatory on
/// its own with axis chrome.
struct TrendChart: View {
    let points: [(date: Date, value: Double)]
    var height: CGFloat = 60

    var body: some View {
        Chart(points, id: \.date) { point in
            LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                .foregroundStyle(Color.primary)
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                .foregroundStyle(Color.primary)
                .symbolSize(14)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trend over time")
        .accessibilityValue(accessibilitySummary)
    }

    /// Without this, Swift Charts fits the y-axis tightly to the data's
    /// own min/max, so the highest point sits pinned to the very top
    /// edge of the frame and the lowest to the very bottom — which is
    /// why the line looked like it was "sitting at the top" rather than
    /// floating with headroom the way Apple's own trend charts do.
    /// Padding the domain on both sides leaves room above the high and
    /// below the low, the same visual effect as showing a min/mid/max
    /// band rather than stretching the data to fill the full height.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let range = high - low
        let padding = range > 0 ? range * 0.4 : max(abs(low) * 0.1, 1)
        return (low - padding)...(high + padding)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "No data" }
        let low = points.map(\.value).min() ?? first.value
        let high = points.map(\.value).max() ?? first.value
        return "From \(NumberFormat.decimal1(first.value)) to \(NumberFormat.decimal1(last.value)), ranging \(NumberFormat.decimal1(low)) to \(NumberFormat.decimal1(high))"
    }
}
