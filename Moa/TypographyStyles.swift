import SwiftUI

/// Four-tier type scale shared by every section, built entirely on
/// semantic Dynamic Type text styles (never fixed point sizes) so it
/// scales with the user's text-size setting, Bold Text, and Larger
/// Accessibility Sizes without any extra work at call sites. Hierarchy is
/// carried by actual size, not just weight/color — those alone compress
/// to near-indistinguishable once text is scaled up.
///
/// - `headlineValueStyle`: the one headline number per section (steps,
///   resting HR, sleep hours).
/// - `statValueStyle`: grid-cell numbers (HRV, VO2 max, distance...).
/// - `statLabelStyle`: grid-cell captions naming what a stat is.
/// - `supportingTextStyle`: supporting detail — ranges, night/workout counts,
///   anything secondary to a stat's own label/value pair.
extension View {
    func headlineValueStyle() -> some View {
        font(.title2.weight(.semibold))
    }

    func statValueStyle() -> some View {
        font(.headline)
    }

    func statLabelStyle() -> some View {
        font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// A subsection heading like "This week workouts" — distinct from
    /// `statLabelStyle`, which it used to share verbatim with plain
    /// field labels like "Avg steps" sitting right underneath it. Same
    /// font, same weight, same color made a heading that introduces a
    /// whole block visually indistinguishable from a caption naming one
    /// number in it. Bumped one full tier (subheadline vs. caption) so
    /// it reads as a heading without competing with the section's own
    /// title (`.title3.weight(.semibold)`, primary) above it.
    func sectionHeadingStyle() -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// "Not enough nights yet," "No data yet" — a sub-block fallback,
    /// smaller and more muted than `headlineValueStyle`'s own no-data
    /// substitutes (Heart & Vitals' "No data yet," Activity Index's "Not
    /// enough history yet"), which stay headline-sized and primary-colored
    /// since they replace a headline number rather than caption a sub-block.
    func emptyStateCaptionStyle() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
    }

    func supportingTextStyle() -> some View {
        // `.tertiary` measures ~1.7:1 against a white card in light
        // mode — far below WCAG AA's 4.5:1 floor for real content
        // (fine for genuinely decorative/inactive elements, not for
        // ranges and counts someone is meant to read). `.secondary`
        // carries the size-based demotion instead.
        font(.caption2)
            .foregroundStyle(.secondary)
    }

    /// Groups a home-screen section into its own rounded, tinted card
    /// instead of a bare block separated only by a hairline `Divider()`
    /// — gives the eye a place to stop between sections on a screen
    /// that's otherwise one long undifferentiated list of stats.
    func sectionCardStyle() -> some View {
        padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
