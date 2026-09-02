import Foundation
import HealthKit
import Combine

/// One object, shared across the app, responsible for everything
/// HealthKit. Built around a small set of generic fetchers — today's
/// total, today's latest sample, a daily history, plus workout and sleep
/// fetchers that need their own shape — rather than one bespoke query
/// per metric.
@MainActor
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var authorizationError: String?

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let identifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .activeEnergyBurned,
            .appleExerciseTime, .appleStandTime,
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
            .vo2Max, .walkingHeartRateAverage, .heartRateRecoveryOneMinute,
            .basalEnergyBurned, .leanBodyMass, .walkingSpeed
        ]
        for identifier in identifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        types.insert(HKObjectType.workoutType())
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }
        return types
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationError = "Health data isn't available on this device."
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            isAuthorized = true
        } catch {
            authorizationError = error.localizedDescription
        }
    }

    // MARK: - Metric-level convenience

    /// Today's value for any metric, routed to the right fetch strategy.
    func fetchTodayValue(for metric: MetricKind) async -> Double? {
        switch metric {
        case .steps:
            return await fetchTodayTotal(for: .stepCount, unit: .count())
        case .distance:
            return await fetchTodayDistanceTotal()
        case .exerciseMinutes:
            return await fetchTodayTotal(for: .appleExerciseTime, unit: .minute())
        case .standMinutes:
            return await fetchTodayTotal(for: .appleStandTime, unit: .minute())
        case .activeCalories:
            return await fetchTodayTotal(for: .activeEnergyBurned, unit: .kilocalorie())
        case .sleepHours:
            return await fetchTodaySleepSummary()?.asleepHours
        case .sleepEfficiency:
            guard let summary = await fetchTodaySleepSummary(), summary.inBedHours > 0 else { return nil }
            return min(1, summary.asleepHours / summary.inBedHours) * 100
        case .restingHeartRate:
            return await fetchLatestSample(for: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()))
        case .heartRateVariability:
            return await fetchLatestSample(for: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli))
        case .vo2Max:
            // Unit construction for cardio fitness — verify against the
            // current HealthKit docs if this doesn't compile; VO2 max's
            // compound unit string is one of the less common ones.
            return await fetchLatestSample(for: .vo2Max, unit: HKUnit(from: "mL/kg*min"))
        case .walkingHeartRateAverage:
            return await fetchLatestSample(for: .walkingHeartRateAverage, unit: HKUnit.count().unitDivided(by: .minute()))
        case .heartRateRecovery:
            // Identifier name worth double-checking against the SDK
            // version in use — heart rate recovery is a newer addition.
            return await fetchLatestSample(for: .heartRateRecoveryOneMinute, unit: HKUnit.count().unitDivided(by: .minute()))
        }
    }

    // MARK: - Generic fetchers

    /// "Distance" isn't one HealthKit quantity — walking/running (and
    /// hiking, which shares the same identifier), cycling, and swimming
    /// each write to their own type. Reading only
    /// `distanceWalkingRunning` silently drops a day's cycling or
    /// swimming distance instead of reporting it low. One shared list
    /// here feeds both fetchers below through the multi-identifier
    /// overloads of `fetchTodayTotal`/`fetchDailyTotals`, instead of
    /// each duplicating the same three-identifier fan-out by hand.
    /// `distanceIdentifier(for:)` further down encodes the same set a
    /// second time in a different shape (activity type → single
    /// identifier, for one workout's own distance) — keep that in sync
    /// with this list if a new distance-producing type is ever added.
    private static let distanceIdentifiers: [HKQuantityTypeIdentifier] = [
        .distanceWalkingRunning, .distanceCycling, .distanceSwimming
    ]

    private func fetchTodayDistanceTotal() async -> Double? {
        await fetchTodayTotal(for: Self.distanceIdentifiers, unit: .meter())
    }

    /// Same all-activity-types summing as `fetchTodayDistanceTotal`, one
    /// value per day, for building a distance history/range/average.
    func fetchDistanceHistory(days: Int) async -> [Double] {
        await fetchDailyTotals(for: Self.distanceIdentifiers, unit: .meter(), days: days)
    }

    /// Sums `fetchTodayTotal` across several identifiers, fetched
    /// concurrently — nil only if every identifier came back with no
    /// data, same as the single-identifier version.
    func fetchTodayTotal(for identifiers: [HKQuantityTypeIdentifier], unit: HKUnit) async -> Double? {
        let values = await withTaskGroup(of: Double?.self) { group -> [Double?] in
            for identifier in identifiers {
                group.addTask { await self.fetchTodayTotal(for: identifier, unit: unit) }
            }
            var results: [Double?] = []
            for await value in group { results.append(value) }
            return results
        }.compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    /// Sums `fetchDailyTotals` across several identifiers, day by day —
    /// safe to add element-wise since every identifier's history is
    /// zero-filled to exactly `days` entries (see `fetchDailyTotals`'s
    /// own doc comment), never a shorter array.
    func fetchDailyTotals(for identifiers: [HKQuantityTypeIdentifier], unit: HKUnit, days: Int,
                           option: HKStatisticsOptions = .cumulativeSum) async -> [Double] {
        let histories = await withTaskGroup(of: [Double].self) { group -> [[Double]] in
            for identifier in identifiers {
                group.addTask { await self.fetchDailyTotals(for: identifier, unit: unit, days: days, option: option) }
            }
            var results: [[Double]] = []
            for await history in group { results.append(history) }
            return results
        }
        guard let first = histories.first else { return [] }
        return histories.dropFirst().reduce(first) { partial, next in zip(partial, next).map(+) }
    }

    /// `option` should be `.discreteAverage` for metrics HealthKit
    /// samples many times a day (walking speed logs one reading per
    /// walking bout, so a same-day average is the meaningful "today"
    /// figure — unlike `fetchLatestSample`, which would just be the most
    /// recent bout and could be stale from yesterday evening if today's
    /// walking hasn't started yet) and `.cumulativeSum` (the default,
    /// matching `fetchDailyTotals`'s own default) for everything else.
    func fetchTodayTotal(for identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                          option: HKStatisticsOptions = .cumulativeSum) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let (start, end) = todayRange()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: option) { _, result, _ in
                let value = option == .cumulativeSum
                    ? result?.sumQuantity()?.doubleValue(for: unit)
                    : result?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    func fetchLatestSample(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples as? [HKQuantitySample])?.first?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            healthStore.execute(query)
        }
    }

    /// One value per day for the last `days` days, ending yesterday —
    /// today is deliberately excluded, matching BaselineEngine's rule
    /// that an in-progress day never gets compared against a full-day
    /// average. `option` should be `.discreteAverage` for resting heart
    /// rate and `.cumulativeSum` (the default) for everything else.
    func fetchDailyTotals(for identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int,
                           option: HKStatisticsOptions = .cumulativeSum) async -> [Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }

        var interval = DateComponents()
        interval.day = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                      options: option, anchorDate: start, intervalComponents: interval)
            query.initialResultsHandler = { _, results, _ in
                var values: [Double] = []
                results?.enumerateStatistics(from: start, to: end) { stats, _ in
                    let value: Double?
                    if option == .cumulativeSum {
                        value = stats.sumQuantity()?.doubleValue(for: unit)
                    } else {
                        value = stats.averageQuantity()?.doubleValue(for: unit)
                    }
                    values.append(value ?? 0)
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Workouts

    struct WorkoutSummary: Identifiable {
        let id = UUID()
        let activityType: HKWorkoutActivityType
        let startDate: Date
        let duration: TimeInterval
        let totalEnergyBurned: Double?
        /// Meters, from whichever distance quantity actually applies to
        /// this activity type — nil for types HealthKit has no distance
        /// quantity for (strength, yoga, HIIT, etc.), not a missing-data
        /// gap to fill in.
        let distance: Double?

        var isStrengthTraining: Bool {
            activityType == .traditionalStrengthTraining || activityType == .functionalStrengthTraining
        }

        /// Explicit allowlist of continuous-effort types where heart
        /// rate zones are a meaningful read on session intensity — not
        /// "everything but strength", since intermittent or low-
        /// intensity types (yoga, core work) would show noise rather
        /// than a genuine effort signal.
        var isCardio: Bool {
            switch activityType {
            case .running, .walking, .cycling, .swimming, .hiking, .elliptical, .rowing, .highIntensityIntervalTraining:
                return true
            default:
                return false
            }
        }

        var typeName: String {
            switch activityType {
            case .running: return "Running"
            case .walking: return "Walking"
            case .cycling: return "Cycling"
            case .swimming: return "Swimming"
            case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
            case .yoga: return "Yoga"
            case .highIntensityIntervalTraining: return "HIIT"
            case .hiking: return "Hiking"
            case .coreTraining: return "Core"
            case .elliptical: return "Elliptical"
            case .rowing: return "Rowing"
            default: return "Workout"
            }
        }
    }

    /// The distance quantity HealthKit actually tracks for a given
    /// activity type — there's no single generic "distance" statistic,
    /// and most types (strength, yoga, HIIT...) have none at all.
    private nonisolated static func distanceIdentifier(for activityType: HKWorkoutActivityType) -> HKQuantityTypeIdentifier? {
        switch activityType {
        case .running, .walking, .hiking: return .distanceWalkingRunning
        case .cycling: return .distanceCycling
        case .swimming: return .distanceSwimming
        default: return nil
        }
    }

    func fetchWorkouts(daysBack: Int) async -> [WorkoutSummary] {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout])?.map { workout -> WorkoutSummary in
                    let distanceValue = Self.distanceIdentifier(for: workout.workoutActivityType).flatMap {
                        workout.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter())
                    }
                    return WorkoutSummary(
                        activityType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        duration: workout.duration,
                        totalEnergyBurned: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?.doubleValue(for: .kilocalorie()),
                        distance: distanceValue
                    )
                } ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    /// Total resistance-tagged workout duration over the window, in
    /// minutes — feeds both the Activity Index's strength component and
    /// Movement's own "Strength" figure, which now shows weekly minutes
    /// against a real target rather than a binary day count.
    func fetchStrengthMinutes(days: Int) async -> Double {
        let workouts = await fetchWorkouts(daysBack: days)
        return workouts.filter(\.isStrengthTraining).reduce(0) { $0 + $1.duration / 60 }
    }

    /// Same total as `fetchStrengthMinutes`, broken out one value per
    /// day over the last `days` days ending yesterday (matching
    /// `fetchDailyTotals`'s convention) — so Movement's "Strength
    /// minutes" stat can build a personal range the same way every
    /// other stat in that grid already does.
    func fetchStrengthMinutesHistory(days: Int) async -> [Double] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }

        let workouts = await fetchWorkouts(daysBack: days)
        var minutesByDay: [Date: Double] = [:]
        for workout in workouts where workout.isStrengthTraining {
            let day = calendar.startOfDay(for: workout.startDate)
            minutesByDay[day, default: 0] += workout.duration / 60
        }

        var result: [Double] = []
        var day = start
        while day < end {
            result.append(minutesByDay[day] ?? 0)
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? end
        }
        return result
    }

    /// A NEAT proxy: today's active energy minus the energy burned
    /// specifically during logged workouts, leaving an estimate of
    /// everything else — walking, fidgeting, general daily movement.
    /// HealthKit doesn't expose a separate "calories from steps" figure
    /// to subtract on its own, so workout time is the only clean
    /// decomposition available.
    func fetchTodayNEAT() async -> Double? {
        guard let totalActive = await fetchTodayValue(for: .activeCalories) else { return nil }
        let todaysWorkouts = (await fetchWorkouts(daysBack: 1)).filter { Calendar.current.isDateInToday($0.startDate) }
        let workoutEnergy = todaysWorkouts.reduce(0.0) { $0 + ($1.totalEnergyBurned ?? 0) }
        return max(0, totalActive - workoutEnergy)
    }

    /// Same decomposition as `fetchTodayNEAT` (active energy minus
    /// workout energy), one value per day, over the same "ending
    /// yesterday" window `fetchDailyTotals` uses.
    func fetchNEATHistory(days: Int) async -> [Double] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }

        async let activeHistory = fetchDailyTotals(for: .activeEnergyBurned, unit: .kilocalorie(), days: days)
        async let workouts = fetchWorkouts(daysBack: days)

        var energyByDay: [Date: Double] = [:]
        for workout in await workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            energyByDay[day, default: 0] += workout.totalEnergyBurned ?? 0
        }

        var neat: [Double] = []
        var day = start
        for active in await activeHistory {
            neat.append(max(0, active - (energyByDay[day] ?? 0)))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        return neat
    }

    // MARK: - Sleep

    struct SleepSummary {
        let asleepHours: Double
        let inBedHours: Double
    }

    struct SleepNightSummary {
        let date: Date          // credited to the wake day
        let asleepHours: Double
        let interruptionMinutes: Double
        let bedStart: Date?
        let wakeEnd: Date?
    }

    /// Last night's sleep, for the home-screen headline and efficiency.
    func fetchTodaySleepSummary() async -> SleepSummary? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let end = Date()
        let start = Calendar.current.date(byAdding: .hour, value: -24, to: end) ?? end
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let categorySamples = (samples as? [HKCategorySample]) ?? []
                var asleep = 0.0, inBed = 0.0
                for sample in categorySamples {
                    let duration = sample.endDate.timeIntervalSince(sample.startDate)
                    if sample.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                        inBed += duration
                    } else {
                        asleep += duration
                    }
                }
                guard asleep > 0 || inBed > 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: SleepSummary(asleepHours: asleep / 3600, inBedHours: inBed / 3600))
            }
            healthStore.execute(query)
        }
    }

    /// Night-by-night sleep detail for the last `days` nights, powering
    /// regularity (median/earliest/latest bedtime), the sleep score's
    /// consistency and interruption components, and the "after a
    /// workout" flag. Each sample is credited to the day it *ended* on,
    /// matching how people think about "last night". Runs through
    /// `Date()` (now) rather than stopping at midnight — a night that
    /// ends after midnight (nearly all of them) would otherwise have
    /// its post-midnight samples excluded, silently falling back to an
    /// older, more complete night instead of the real last night.
    func fetchSleepNights(days: Int) async -> [SleepNightSummary] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let categorySamples = ((samples as? [HKCategorySample]) ?? []).sorted { $0.startDate < $1.startDate }

                var buckets: [Date: [HKCategorySample]] = [:]
                for sample in categorySamples {
                    let day = Self.sleepNightBucket(for: sample.endDate, calendar: calendar)
                    buckets[day, default: []].append(sample)
                }

                let nights: [SleepNightSummary] = buckets.map { day, samples in
                    // Excludes both `.inBed` and `.awake` — the latter
                    // is genuine time spent awake overnight (Apple's own
                    // sleep-stage tracking logs it explicitly), and
                    // counting it as "asleep" both overstates duration
                    // and hides real awakenings from the gap-based
                    // interruption calculation below, since a merged-in
                    // awake segment leaves no detectable gap.
                    let asleep = samples
                        .filter {
                            $0.value != HKCategoryValueSleepAnalysis.inBed.rawValue &&
                            $0.value != HKCategoryValueSleepAnalysis.awake.rawValue
                        }
                        .sorted { $0.startDate < $1.startDate }
                    let asleepSeconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

                    // Interruptions: gaps between consecutive asleep
                    // samples, i.e. moments awake in the middle of the
                    // night rather than before falling asleep or after
                    // waking for good.
                    var interruptionSeconds = 0.0
                    if asleep.count > 1 {
                        for i in 1..<asleep.count {
                            let gap = asleep[i].startDate.timeIntervalSince(asleep[i - 1].endDate)
                            if gap > 0 { interruptionSeconds += gap }
                        }
                    }

                    return SleepNightSummary(
                        date: day,
                        asleepHours: asleepSeconds / 3600,
                        interruptionMinutes: interruptionSeconds / 60,
                        bedStart: samples.first?.startDate,
                        // The whole session's latest end, from the
                        // unfiltered `samples` — same source `bedStart`
                        // already uses — not just `asleep`'s. A brief
                        // awakening with no further asleep-classified
                        // sample afterward (dozing, lying in bed, or
                        // just not deep enough to register a stage)
                        // would otherwise truncate wakeEnd at that
                        // awakening instead of the actual time spent
                        // getting up. This also avoids the previous
                        // start-sorted-`.last` issue, since real
                        // HealthKit sleep data can have overlapping
                        // samples (iPhone- and Watch-logged stages for
                        // the same night both present as separate
                        // entries) that a start-date sort doesn't
                        // reliably order by end time.
                        wakeEnd: samples.map(\.endDate).max()
                    )
                }.sorted { $0.date < $1.date }

                continuation.resume(returning: nights)
            }
            healthStore.execute(query)
        }
    }

    /// Which night a sample belongs to, using a 6pm day boundary instead
    /// of midnight — the same technique `SleepRegularity` already uses
    /// for the identical cross-midnight problem. Plain
    /// `calendar.startOfDay` bucketing looked right for a whole session
    /// at a glance but silently merged two different nights whenever
    /// bedtime was before midnight: a short sample from that session
    /// ending at, say, 23:58 falls on the same calendar day as that
    /// morning's *previous* night's wake-up, so both landed in one
    /// bucket — and since 23:58 is numerically later than 8:34am same
    /// day, picking the max end time inside that merged bucket
    /// deterministically returned the next night's bedtime fragment as
    /// "wakeEnd" instead of the real morning wake. Anchoring the
    /// rollover at 6pm means a whole bedtime-to-wake session almost
    /// never spans two buckets, since virtually no one's sleep both
    /// starts and ends within the same 6pm-to-6pm window.
    ///
    /// `nonisolated`: this project defaults every type to `@MainActor`
    /// isolation, but `HKSampleQuery`'s completion closure (where this
    /// is called, in `fetchSleepNights` below) runs in a plain
    /// synchronous, non-isolated HealthKit callback context — not the
    /// main actor, and not `async`, so there's no way to hop onto it
    /// there anyway. This function is pure (no shared state, no UI), so
    /// it has no real reason to be actor-isolated in the first place.
    private nonisolated static func sleepNightBucket(for date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        guard let sixPM = calendar.date(byAdding: .hour, value: 18, to: dayStart) else { return dayStart }
        // On/after 6pm: an evening sample, belonging to the night that
        // wakes tomorrow. Before 6pm: belongs to the night that began
        // yesterday evening — same bucket label the original
        // `startOfDay(for: endDate)` already used for a normal morning
        // wake, so this only changes behavior for the evening case.
        if date >= sixPM {
            return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        }
        return dayStart
    }

    // MARK: - Heart rate samples (for max HR resolution, zones, VILPA)

    /// Age from the `dateOfBirth` characteristic — synchronous, always
    /// available if the person has entered a birthdate in Health,
    /// unlike everything else here which needs a query.
    func fetchAge() -> Int? {
        guard let components = try? healthStore.dateOfBirthComponents(),
              let birthDate = Calendar.current.date(from: components) else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Raw heart rate samples recorded during logged workouts over the
    /// last `daysBack` days — the input to the 95th-percentile max HR
    /// calculation. One query per workout; fine at the scale a personal
    /// app deals with, not something to do over hundreds of workouts.
    func fetchWorkoutHeartRateSamples(daysBack: Int) async -> [Double] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let workouts = await fetchWorkouts(daysBack: daysBack)
        var allValues: [Double] = []

        for workout in workouts {
            let end = workout.startDate.addingTimeInterval(workout.duration)
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: end, options: .strictStartDate)
            let values: [Double] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    let values = (samples as? [HKQuantitySample])?.map {
                        $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    } ?? []
                    continuation.resume(returning: values)
                }
                healthStore.execute(query)
            }
            allValues.append(contentsOf: values)
        }
        return allValues
    }

    /// Timestamped heart rate samples for each workout, keyed by its
    /// id — average HR and (for cardio types) zone breakdown per
    /// session. One query per workout, same tradeoff as
    /// `fetchWorkoutHeartRateSamples`: fine at the scale of a day's
    /// workouts, not something to run over a long history.
    func fetchHeartRateSamples(for workouts: [WorkoutSummary]) async -> [UUID: [(date: Date, bpm: Double)]] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [:] }
        var result: [UUID: [(date: Date, bpm: Double)]] = [:]

        for workout in workouts {
            let end = workout.startDate.addingTimeInterval(workout.duration)
            let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: end, options: .strictStartDate)
            let values: [(date: Date, bpm: Double)] = await withCheckedContinuation { continuation in
                let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                    let values = (samples as? [HKQuantitySample])?.map {
                        (date: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                    } ?? []
                    continuation.resume(returning: values)
                }
                healthStore.execute(query)
            }
            result[workout.id] = values
        }
        return result
    }

    /// Every heart rate sample recorded today, with timestamps — used
    /// to bucket minutes into zones and to detect VILPA bursts.
    func fetchTodayHeartRateSamples() async -> [(date: Date, bpm: Double)] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let (start, end) = todayRange()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    (date: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Every heart rate sample over the last `days` days, ending
    /// yesterday — same "ending yesterday" window as `fetchDailyTotals`,
    /// for computing history like the Vigorous Moments range.
    func fetchHeartRateSamples(days: Int) async -> [(date: Date, bpm: Double)] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    (date: $0.startDate, bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Every HRV (SDNN) sample over the last `days` days, with
    /// timestamps — used to compute per-night overnight averages rather
    /// than one figure blending sleeping and waking readings together.
    /// Unlike `fetchHeartRateSamples`, this deliberately runs through
    /// `Date()` (now) rather than stopping at the start of today: sleep
    /// windows extend past midnight, so a night that isn't over yet by
    /// calendar-day accounting still needs its early-morning samples
    /// included.
    func fetchHRVSamples(days: Int) async -> [(date: Date, ms: Double)] {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else { return [] }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    (date: $0.startDate, ms: $0.quantity.doubleValue(for: .secondUnit(with: .milli)))
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Raw VO2 max readings, one per qualifying outdoor walk/run —
    /// sparse and irregular (Apple's algorithm only writes a new sample
    /// every so often, not daily), which is exactly why this returns
    /// actual sample dates rather than a `fetchDailyTotals`-style daily
    /// bucket array: a trend line needs to skip the gaps between real
    /// readings, not plot zero for every day nothing was recorded.
    func fetchVO2MaxSamples(days: Int) async -> [(date: Date, value: Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: .vo2Max) else { return [] }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    (date: $0.startDate, value: $0.quantity.doubleValue(for: HKUnit(from: "mL/kg*min")))
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Raw sleep-analysis category samples over `days` days, running
    /// through `Date()` for the same reason `fetchHRVSamples` does —
    /// sleep spans midnight, so a window ending at the start of today
    /// would cut off last night's early-morning samples. Unlike
    /// `fetchSleepNights`, which aggregates into per-night summaries
    /// credited to the wake day, this hands back the raw start/end/value
    /// triples needed to build minute-by-minute epoch grids (SRI),
    /// which need actual midnight-to-midnight calendar days rather than
    /// wake-day-bucketed nights.
    func fetchSleepCategorySamples(days: Int) async -> [(start: Date, end: Date, value: Int)] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let values = (samples as? [HKCategorySample])?.map {
                    (start: $0.startDate, end: $0.endDate, value: $0.value)
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Helpers

    private func todayRange() -> (Date, Date) {
        let now = Date()
        return (Calendar.current.startOfDay(for: now), now)
    }
}
