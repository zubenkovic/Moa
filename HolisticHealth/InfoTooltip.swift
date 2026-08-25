import SwiftUI
import UIKit

/// A small "explain this" button for any stat that isn't self-evident at
/// a glance — Activity Index, HR zones, VILPA, Sleep Score weighting.
/// Keeps explainer copy sitting right next to the number instead of
/// buried in a README nobody opens.
struct InfoTooltip: View {
    let text: String
    @State private var isPresented = false

    private static let maxWidth: CGFloat = 280
    private static let padding: CGFloat = 16

    /// SwiftUI's `.popover` sizes itself from `preferredContentSize`,
    /// which flexible constraints (`.frame(maxWidth:)`, `.fixedSize()`)
    /// don't reliably feed on iOS — the popover falls back to a default
    /// box instead of measuring the wrapped text. Measuring the text
    /// with UIKit and handing the popover an exact frame sidesteps that
    /// entirely.
    private var popoverSize: CGSize {
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let availableWidth = Self.maxWidth - Self.padding * 2
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: Self.maxWidth, height: ceil(bounding.height) + Self.padding * 2)
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        // Expands only the *hit-test* region to the 44x44pt HIG minimum,
        // without inflating the button's layout size — these icons sit
        // inline next to labels, so growing the frame itself would blow
        // up row height and spacing throughout every stat row that uses one.
        .contentShape(Rectangle().inset(by: -12))
        .popover(isPresented: $isPresented) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(Self.padding)
                .frame(width: popoverSize.width, height: popoverSize.height)
                .presentationCompactAdaptation(.popover)
        }
    }
}
