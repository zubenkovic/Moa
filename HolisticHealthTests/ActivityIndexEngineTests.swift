import XCTest

final class ActivityIndexEngineTests: XCTestCase {

    // MARK: - strength component (weekly minutes / 60, capped at 100%)

    func testStrength_zeroMinutes_scoresZero() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 0, sleepScoreAvg: 0
        )
        XCTAssertEqual(result.strengthPercent, 0)
        XCTAssertEqual(result.strengthPercentRaw, 0)
    }

    func testStrength_30Minutes_scoresHalfCredit() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 30, sleepScoreAvg: 0
        )
        XCTAssertEqual(result.strengthPercent, 50)
        XCTAssertEqual(result.strengthPercentRaw, 50)
    }

    func testStrength_60Minutes_scoresFullCredit() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 60, sleepScoreAvg: 0
        )
        XCTAssertEqual(result.strengthPercent, 100)
        XCTAssertEqual(result.strengthPercentRaw, 100)
    }

    func testStrength_90Minutes_cappedAt100ButRawExceedsIt() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 90, sleepScoreAvg: 0
        )
        XCTAssertEqual(result.strengthPercent, 100, "capped component must not exceed 100% even when the raw ratio does")
        XCTAssertEqual(result.strengthPercentRaw, 150)
    }

    // A single long session hitting the weekly minutes target should
    // score identically to several shorter ones totaling the same
    // minutes — no per-session floor, by design.
    func testStrength_noSessionLengthFloor_onlyTotalMinutesMatter() {
        let result = ActivityIndexEngine.compute(
            sevenDayAvgSteps: 0, weeklyModerateMinutes: 0, weeklyStrengthMinutes: 60, sleepScoreAvg: 0
        )
        XCTAssertEqual(result.strengthPercent, 100)
    }
}
