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

    /// `.providedUnit` rather than `.naturalScale`: we've already picked
    /// the unit ourselves (km vs. mi, by measurement system) in
    /// `distance(meters:)` below, so this should render exactly that
    /// unit rather than have `MeasurementFormatter` rescale a short
    /// distance down to meters/feet on its own. `.medium`, not `.short`
    /// — `.short` renders "9.3mi" with no space in en_US/en_GB (verified
    /// directly) while still spacing "14,9 km" in metric locales, an
    /// inconsistency that would sit right next to "105 min" elsewhere on
    /// the same line. `.medium` keeps the abbreviation ("mi"/"km", not
    /// "miles"/"Kilometer") while spacing consistently everywhere.
    private static let distanceFormatter: MeasurementFormatter = {
        let formatter = MeasurementFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        formatter.numberFormatter = decimal1Formatter
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

    /// Kilometers in metric-system regions, miles in the US and UK (both
    /// non-metric per `Locale.MeasurementSystem`, which matches how
    /// those regions actually measure road/running distance despite the
    /// UK being metric for most other things) — "14.9 km" in Germany,
    /// "9.3 mi" in the US, converted from the meters HealthKit always
    /// reports in, the same way `int`/`decimal1` already vary their
    /// separators by Region rather than a single hardcoded format.
    static func distance(meters: Double) -> String {
        let unit: UnitLength = Locale.autoupdatingCurrent.measurementSystem == .metric ? .kilometers : .miles
        let measurement = Measurement(value: meters, unit: UnitLength.meters).converted(to: unit)
        return distanceFormatter.string(from: measurement)
    }
}
