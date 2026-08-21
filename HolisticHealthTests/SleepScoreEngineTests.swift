import XCTest

final class SleepScoreEngineTests: XCTestCase {
    // Isolate the duration sub-score by holding consistency and
    // interruptions at full credit (0 variance, 0 interruption
    // minutes), so `score` - 50 reflects duration's own contribution
    // out of its 50-point weight.

    private func durationOnlyScore(_ hours: Double) -> Int {
        SleepScoreEngine.score(asleepHours: hours, bedtimeVarianceMinutes: 0, interruptionMinutes: 0)
    }

    func testDuration_belowFourHours_zeroCredit() {
        XCTAssertEqual(durationOnlyScore(3), 50, "duration score floors at 0 rather than going negative")
    }

    func testDuration_atFourHours_zeroCredit() {
        XCTAssertEqual(durationOnlyScore(4), 50)
    }

    func testDuration_atSevenHours_fullCredit() {
        XCTAssertEqual(durationOnlyScore(7), 100)
    }

    func testDuration_atEightHours_fullCredit() {
        XCTAssertEqual(durationOnlyScore(8), 100)
    }

    func testDuration_atNineHours_fullCredit() {
        XCTAssertEqual(durationOnlyScore(9), 100)
    }

    func testDuration_atTwelveHours_zeroCredit() {
        XCTAssertEqual(durationOnlyScore(12), 50)
    }

    func testDuration_aboveTwelveHours_zeroCredit() {
        XCTAssertEqual(durationOnlyScore(13), 50, "duration score floors at 0 rather than going negative past 12h")
    }

    func testDuration_midTaperBelowRange_halfCredit() {
        // 5.5h is halfway between the 4h floor and the 7h plateau start.
        XCTAssertEqual(durationOnlyScore(5.5), 75)
    }

    func testDuration_midTaperAboveRange_halfCredit() {
        // 10.5h is halfway between the 9h plateau end and the 12h floor.
        XCTAssertEqual(durationOnlyScore(10.5), 75)
    }

    func testDuration_tenHours_scoresLowerThanNineHours() {
        // Regression guard for the trapezoid replacing the old
        // symmetric taper: a 10h night must no longer share 9h's full
        // credit, and must score strictly worse than 9h.
        XCTAssertLessThan(durationOnlyScore(10), durationOnlyScore(9))
    }
}
