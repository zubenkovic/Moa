import Foundation

/// Every number in this app groups thousands and picks a decimal
/// separator the way the device's own Region setting says to — the same
/// native behavior `DateFormatter` already gets for free. Plain `Int`
/// interpolation and `String(format: "%.1f", ...)` both fall short of
/// that in their own way: `Int` interpolation never groups thousands at
/// all regardless of locale (that's how a step count ends up as "8412"
/// sitting next to a hand-typed "7,000"), and `%f`'s locale-aware decimal
/// point isn't paired with any grouping, since `printf`-style specifiers
/// don't group. Routing both through `NumberFormatter` fixes both at
/// once, and `.autoupdatingCurrent` keeps it in sync if the user changes
/// Region while the app is running.
enum NumberFormat {
    private static let intFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let decimal1Formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// Whole number, thousands-grouped per the device's Region setting
    /// — "8,412" in the US, "8.412" in Germany, "8 412" in France.
    static func int(_ value: Double) -> String {
        intFormatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
    }

    static func int(_ value: Int) -> String {
        intFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// One decimal place, same per-Region grouping and decimal separator
    /// — "2.8" in the US, "2,8" in Germany.
    static func decimal1(_ value: Double) -> String {
        decimal1Formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
