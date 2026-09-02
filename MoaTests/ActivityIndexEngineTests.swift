import XCTest

final class ActivityIndexEngineTests: XCTestCase {

    // MARK: - raw pass-through (no percent-of-target, no capping, no scoring)

    func testZeroInputs_passThroughAsZero() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 0, avgSleepHours: 0
        )
        XCTAssertEqual(result.avgSteps, 0)
        XCTAssertEqual(result.weeklyMinutes, 0)
        XCTAssertEqual(result.weeklyStrengthMinutes, 0)
        XCTAssertEqual(result.avgSleepHours, 0)
    }

    func testStrengthMinutes_passThroughUnchanged() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 30, avgSleepHours: 0
        )
        XCTAssertEqual(result.weeklyStrengthMinutes, 30)
    }

    // No capping: exceeding a target should show as the real number, not
    // clamped — that's the whole point of dropping percent-of-target.
    func testStrengthMinutes_exceedingTarget_isNotCapped() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 90, avgSleepHours: 0
        )
        XCTAssertEqual(result.weeklyStrengthMinutes, 90, "raw values pass through uncapped, even past the 60-minute target")
    }

    func testSteps_passThroughUnchanged() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 12000, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 0, avgSleepHours: 0
        )
        XCTAssertEqual(result.avgSteps, 12000)
    }

    func testSleepHours_passThroughUnchanged_noScoring() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 0, avgSleepHours: 7.5
        )
        XCTAssertEqual(result.avgSleepHours, 7.5, "sleep is raw average duration now, not a computed 0\u{2013}100 score")
    }
}
