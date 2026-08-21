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
            .stepCount, .distanceWalkingRunning, .activeEnergyBurned,
            .appleExerciseTime, .appleStandTime,
            .restingHeartRate, .heartRateVariabilitySDNN, .heartRate,
            .vo2Max, .walkingHeartRateAverage, .heartRateRecoveryOneMinute,
            .basalEnergyBurned, .leanBodyMass
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
            return await fetchTodayTotal(for: .distanceWalkingRunning, unit: .meter())
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

    func fetchTodayTotal(for identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let (start, end) = todayRange()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
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

        var isStrengthTraining: Bool {
            activityType == .traditionalStrengthTraining || activityType == .functionalStrengthTraining
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

    func fetchWorkouts(daysBack: Int) async -> [WorkoutSummary] {
        let calendar = Calendar.current
        let end = Date()
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: end) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let workouts = (samples as? [HKWorkout])?.map { workout in
                    WorkoutSummary(
                        activityType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        duration: workout.duration,
                        totalEnergyBurned: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                            .sumQuantity()?.doubleValue(for: .kilocalorie())
                    )
                } ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    /// Which of the last `days` days had at least one logged workout of
    /// any kind — "Active days" on the Movement section.
    func fetchActiveDayFlags(days: Int) async -> [Bool] {
        let workouts = await fetchWorkouts(daysBack: days)
        return dayFlags(from: workouts, days: days) { _ in true }
    }

    /// Same idea, restricted to resistance-tagged workouts — "Strength
    /// days". Walking counts toward Active days but never Strength days;
    /// these answer genuinely different research questions and
    /// shouldn't be blended into one ambiguous count.
    func fetchStrengthDayFlags(days: Int) async -> [Bool] {
        let workouts = await fetchWorkouts(daysBack: days)
        return dayFlags(from: workouts, days: days) { $0.isStrengthTraining }
    }

    /// Total resistance-tagged workout duration over the window, in
    /// minutes — feeds the Activity Index's strength component, which
    /// scores weekly volume rather than the session count `fetchStrengthDayFlags`
    /// answers for the Movement section's "Strength days" stat.
    func fetchStrengthMinutes(days: Int) async -> Double {
        let workouts = await fetchWorkouts(daysBack: days)
        return workouts.filter(\.isStrengthTraining).reduce(0) { $0 + $1.duration / 60 }
    }

    private func dayFlags(from workouts: [WorkoutSummary], days: Int, matching: (WorkoutSummary) -> Bool) -> [Bool] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let matchingDays = Set(workouts.filter(matching).map { calendar.startOfDay(for: $0.startDate) })
        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return matchingDays.contains(day)
        }
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
                    let day = calendar.startOfDay(for: sample.endDate)
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
                        wakeEnd: asleep.last?.endDate
                    )
                }.sorted { $0.date < $1.date }

                continuation.resume(returning: nights)
            }
            healthStore.execute(query)
        }
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
