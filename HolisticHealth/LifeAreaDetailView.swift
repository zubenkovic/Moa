import SwiftUI

/// One template shared by all three areas — each just points at a
/// different `detailMetrics` list (see LifeArea.swift), so this view
/// never needs area-specific branching.
struct LifeAreaDetailView: View {
    let area: LifeArea

    @StateObject private var healthKit = HealthKitManager.shared
    @State private var values: [MetricKind: Double] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(area.subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)

                ForEach(area.detailMetrics, id: \.self) { metric in
                    HStack {
                        Text(metric.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let value = values[metric] {
                            Text(MetricKind.format(value, for: metric))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No data yet")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 12)
                    Divider()
                }
            }
            .padding()
        }
        .navigationTitle(area.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for metric in area.detailMetrics {
                values[metric] = await healthKit.fetchTodayValue(for: metric)
            }
        }
    }
}

#Preview {
    NavigationStack {
        LifeAreaDetailView(area: .movement)
    }
}
