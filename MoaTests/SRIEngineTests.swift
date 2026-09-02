import XCTest

final class SRIEngineTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ offset: Int, from reference: Date = Calendar.current.startOfDay(for: Date())) -> Date {
        calendar.date(byAdding: .day, value: offset, to: reference)!
    }

    // MARK: - pairwiseSRI

    func testPairwiseSRI_identicalDays_returns100() {
        let profile = [Bool](repeating: true, count: SRIEngine.epochsPerDay / 2) + [Bool](repeating: false, count: SRIEngine.epochsPerDay / 2)
        XCTAssertEqual(SRIEngine.pairwiseSRI(profile, profile), 100, accuracy: 0.0001)
    }

    func testPairwiseSRI_completelyInvertedDays_returnsMinus100() {
        let dayA = [Bool](repeating: true, count: SRIEngine.epochsPerDay)
        let dayB = [Bool](repeating: false, count: SRIEngine.epochsPerDay)
        XCTAssertEqual(SRIEngine.pairwiseSRI(dayA, dayB), -100, accuracy: 0.0001)
    }

    func testPairwiseSRI_halfMatching_returnsZero() {
        // Half the epochs agree, half disagree — should land exactly at
        // the midpoint of the -100...+100 scale, i.e. 0.
        var dayA = [Bool](repeating: true, count: SRIEngine.epochsPerDay)
        var dayB = [Bool](repeating: true, count: SRIEngine.epochsPerDay)
        for i in 0..<(SRIEngine.epochsPerDay / 2) {
            dayB[i] = false
        }
        _ = dayA // dayA stays all-true; dayB is half true/half false
        XCTAssertEqual(SRIEngine.pairwiseSRI(dayA, dayB), 0, accuracy: 0.2)
    }

    // MARK: - dailyEpochProfiles

    func testDailyEpochProfiles_excludesInBedAndAwake() {
        let dayStart = day(0)
        // inBed 0, asleepCore 3, awake 2, asleepREM 5 — only the two
        // asleep-stage samples should end up marked true.
        let samples: [(start: Date, end: Date, value: Int)] = [
            (dayStart, dayStart.addingTimeInterval(60 * 60), 0),
            (dayStart.addingTimeInterval(60 * 60), dayStart.addingTimeInterval(2 * 60 * 60), 3),
            (dayStart.addingTimeInterval(2 * 60 * 60), dayStart.addingTimeInterval(2.5 * 60 * 60), 2),
            (dayStart.addingTimeInterval(2.5 * 60 * 60), dayStart.addingTimeInterval(3 * 60 * 60), 5),
        ]
        let profiles = SRIEngine.dailyEpochProfiles(samples: samples, days: [dayStart], calendar: calendar)
        let profile = profiles[dayStart]!

        XCTAssertFalse(profile[30]) // within the inBed hour (0-59)
        XCTAssertTrue(profile[90]) // within the asleepCore hour (60-119)
        XCTAssertFalse(profile[135]) // within the awake half-hour (120-149)
        XCTAssertTrue(profile[170]) // within the asleepREM half-hour (150-179)
    }

    func testDailyEpochProfiles_clipsSampleAtDayBoundary() {
        // A sample spanning midnight should only mark epochs within
        // each respective calendar day, not bleed into the other.
        let dayZero = day(0)
        let dayOne = day(1)
        let samples: [(start: Date, end: Date, value: Int)] = [
            (dayZero.addingTimeInterval(23 * 60 * 60), dayOne.addingTimeInterval(60 * 60), 3) // 11pm-1am
        ]
        let profiles = SRIEngine.dailyEpochProfiles(samples: samples, days: [dayZero, dayOne], calendar: calendar)

        let profileZero = profiles[dayZero]!
        let profileOne = profiles[dayOne]!
        XCTAssertTrue(profileZero[23 * 60]) // 11pm on day zero
        XCTAssertFalse(profileZero[0]) // midnight belongs to day one, not day zero
        XCTAssertTrue(profileOne[0]) // midnight on day one
        XCTAssertTrue(profileOne[30]) // 12:30am on day one
        XCTAssertFalse(profileOne[61]) // 1:01am, past the sample's end
    }

    // MARK: - windowSRI (the pairwise-comparison + exclusion logic)

    func testWindowSRI_returnsNilWithFewerThanTwoDays() {
        let profiles: [Date: [Bool]] = [day(0): [Bool](repeating: true, count: SRIEngine.epochsPerDay)]
        XCTAssertNil(SRIEngine.windowSRI(profiles: profiles, orderedDays: [day(0)]))
    }

    func testWindowSRI_excludesNightWithZeroData_ratherThanTreatingItAsAMismatch() {
        // Three consecutive identical-schedule days, but the middle one
        // has zero recorded sleep data. If it were wrongly treated as a
        // full mismatch, the average would come out far below 100; the
        // correct behavior is to drop both pairs touching it and still
        // report a perfect score from... actually with the middle day
        // excluded, there are zero valid pairs left (day0-day1 and
        // day1-day2 both touch the empty day), so this specifically
        // checks that no pair is silently kept with the empty profile.
        let realProfile = [Bool](repeating: true, count: SRIEngine.epochsPerDay / 2)
            + [Bool](repeating: false, count: SRIEngine.epochsPerDay / 2)
        let emptyProfile = [Bool](repeating: false, count: SRIEngine.epochsPerDay)

        let profiles: [Date: [Bool]] = [
            day(0): realProfile,
            day(1): emptyProfile,
            day(2): realProfile,
        ]
        let result = SRIEngine.windowSRI(profiles: profiles, orderedDays: [day(0), day(1), day(2)])
        XCTAssertNil(result, "both pairs touch the empty-data day, so no valid pair remains")
    }

    func testWindowSRI_excludesOnlyTheAffectedPair_keepsTheOtherValidPair() {
        // Four days: 0-1 identical (valid pair), 1 has zero data
        // (already covered above), 2-3 identical (valid pair) — but day
        // 1 is empty, so pair (0,1) and (1,2) get dropped, leaving only
        // pair (2,3).
        let profileA = [Bool](repeating: true, count: SRIEngine.epochsPerDay / 2)
            + [Bool](repeating: false, count: SRIEngine.epochsPerDay / 2)
        let emptyProfile = [Bool](repeating: false, count: SRIEngine.epochsPerDay)

        let profiles: [Date: [Bool]] = [
            day(0): profileA,
            day(1): emptyProfile,
            day(2): profileA,
            day(3): profileA,
        ]
        let result = SRIEngine.windowSRI(profiles: profiles, orderedDays: [day(0), day(1), day(2), day(3)])
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.value, 100, accuracy: 0.0001)
        XCTAssertEqual(result!.nightsUsed, 2) // only day(2) and day(3)
    }

    func testWindowSRI_nightsUsedCountsUniqueDaysAcrossPairs() {
        let profile = [Bool](repeating: true, count: SRIEngine.epochsPerDay)
        let profiles: [Date: [Bool]] = [
            day(0): profile, day(1): profile, day(2): profile,
        ]
        let result = SRIEngine.windowSRI(profiles: profiles, orderedDays: [day(0), day(1), day(2)])
        XCTAssertEqual(result?.nightsUsed, 3)
    }

    // MARK: - slidingWindowHistory

    func testSlidingWindowHistory_producesOnePointPerPossibleWindowEnd() {
        let profile = [Bool](repeating: true, count: SRIEngine.epochsPerDay)
        let days = (0..<10).map { day($0) }
        var profiles: [Date: [Bool]] = [:]
        for d in days { profiles[d] = profile }

        // windowLength 8 over 10 days gives windows ending at index 7,8,9 → 3 points.
        let history = SRIEngine.slidingWindowHistory(profiles: profiles, allDaysOldestToNewest: days, windowLength: 8)
        XCTAssertEqual(history.count, 3)
        XCTAssertTrue(history.allSatisfy { abs($0 - 100) < 0.0001 })
    }

    func testSlidingWindowHistory_emptyWhenNotEnoughDays() {
        let profile = [Bool](repeating: true, count: SRIEngine.epochsPerDay)
        let days = (0..<5).map { day($0) }
        var profiles: [Date: [Bool]] = [:]
        for d in days { profiles[d] = profile }

        XCTAssertTrue(SRIEngine.slidingWindowHistory(profiles: profiles, allDaysOldestToNewest: days, windowLength: 8).isEmpty)
    }
}
