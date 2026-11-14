import Foundation
import HealthKit
import Combine

struct DailyEnergy: Codable, Equatable {
    var date: Date
    var resting: Double
    var active: Double
    var updatedAt: Date?
    var sourceName: String?
    var sourceCount: Int?
    var sourceSelectionStrategy: String?

    init(date: Date, resting: Double, active: Double, updatedAt: Date? = nil, sourceName: String? = nil, sourceCount: Int? = nil, sourceSelectionStrategy: String? = nil) {
        self.date = date
        self.resting = resting
        self.active = active
        self.updatedAt = updatedAt
        self.sourceName = sourceName
        self.sourceCount = sourceCount
        self.sourceSelectionStrategy = sourceSelectionStrategy
    }
}

final class HealthKitManager: ObservableObject {
    private struct PendingBodyWeight: Codable {
        let id: UUID
        let kilograms: Double
        let date: Date
    }
    private struct EnergyMeasurement {
        let value: Double
        let sourceName: String
        let sourceCount: Int
        let selectionStrategy: String
    }
    private let healthStore = HKHealthStore()

    @Published private(set) var dailyEnergy: [String: DailyEnergy] = [:]
    @Published private(set) var dailySteps: [String: Int] = [:]
    @Published private(set) var bodyWeights: [BodyMeasurement] = []
    @Published var isAuthorized: Bool = false
    @Published var authorizationError: String?
    @Published var lastWaterSyncMessage: String?
    @Published var lastWeightSyncMessage: String?
    private let waterDayMetadataKey = "HyseWaterDay"
    private let bodyWeightMetadataKey = "HyseBodyWeightID"
    private let calorieEntryMetadataKey = "CalorieEntryID"
    private let micronutrientBackfillKeyPrefix = "health_micronutrients_backfilled_v1_"
    @Published private(set) var dietaryPermissionRevision = 0
    private var dietaryOperations: [(@escaping () -> Void) -> Void] = []
    private var dietaryOperationRunning = false
    private var pendingMicronutrientBackfills: Set<String> = []
    private var micronutrientAuthorizationInFlight = false

    private let micronutrientIdentifiers: [(Micronutrient, HKQuantityTypeIdentifier)] = [
        (.vitaminA, .dietaryVitaminA), (.vitaminC, .dietaryVitaminC),
        (.vitaminD, .dietaryVitaminD), (.vitaminE, .dietaryVitaminE),
        (.vitaminK, .dietaryVitaminK), (.vitaminB6, .dietaryVitaminB6),
        (.vitaminB12, .dietaryVitaminB12), (.folate, .dietaryFolate),
        (.calcium, .dietaryCalcium), (.iron, .dietaryIron),
        (.magnesium, .dietaryMagnesium), (.potassium, .dietaryPotassium),
        (.zinc, .dietaryZinc), (.sodium, .dietarySodium),
        (.iodine, .dietaryIodine), (.selenium, .dietarySelenium)
    ]

    private var micronutrientTypes: [(Micronutrient, HKQuantityType)] {
        micronutrientIdentifiers.compactMap { nutrient, identifier in
            HKQuantityType.quantityType(forIdentifier: identifier).map { (nutrient, $0) }
        }
    }

    private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
    private let restingEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)
    private let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)
    private let energyStorageKey = "daily_health_energy_v1"
    private let stepsStorageKey = "daily_health_steps_v1"
    private let bodyWeightStorageKey = "health_body_weights_v1"
    private let healthConnectedStorageKey = "health_connected_v1"
    private let pendingBodyWeightsStorageKey = "pending_health_body_weights_v1"
    private let refreshThrottle: TimeInterval = 60
    private var bodyWeightRefreshInFlight = false
    private var lastBodyWeightRefreshAt: Date?
    private var stepRefreshesInFlight: Set<String> = []
    private var lastStepRefreshAt: [String: Date] = [:]
    private var energyRefreshesInFlight: Set<String> = []
    private var lastEnergyRefreshAt: [String: Date] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: energyStorageKey),
           let stored = try? JSONDecoder().decode([String: DailyEnergy].self, from: data) {
            dailyEnergy = stored
        }
        if let data = UserDefaults.standard.data(forKey: stepsStorageKey),
           let stored = try? JSONDecoder().decode([String: Int].self, from: data) {
            dailySteps = stored
        }
        if let data = UserDefaults.standard.data(forKey: bodyWeightStorageKey),
           let stored = try? JSONDecoder().decode([BodyMeasurement].self, from: data) {
            bodyWeights = stored.sorted { $0.date < $1.date }
        }
        isAuthorized = UserDefaults.standard.bool(forKey: healthConnectedStorageKey)
        if isAuthorized {
            DispatchQueue.main.async { [weak self] in
                self?.refreshEnergy(around: Date())
                self?.refreshSteps(around: Date())
                self?.refreshBodyWeights()
                self?.startObservingChanges()
                self?.flushPendingBodyWeights()
            }
        }
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        guard isHealthDataAvailable else {
            authorizationError = LanguageStore.localizedString("health.unavailable")
            completion?(false)
            return
        }

        let readTypes: Set<HKObjectType> = Set([
            activeEnergyType,
            restingEnergyType,
            HKQuantityType.quantityType(forIdentifier: .bodyMass),
            stepCountType
        ].compactMap { $0 })

        let shareTypes: Set<HKSampleType> = Set([
            HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed),
            HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            HKQuantityType.quantityType(forIdentifier: .dietarySugar),
            HKQuantityType.quantityType(forIdentifier: .dietaryFiber),
            HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated),
            HKQuantityType.quantityType(forIdentifier: .dietarySodium),
            HKQuantityType.quantityType(forIdentifier: .dietaryWater),
            HKQuantityType.quantityType(forIdentifier: .bodyMass)
        ].compactMap { $0 } + micronutrientTypes.map(\.1))

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.authorizationError = error.localizedDescription
                    completion?(false)
                    return
                }

                self?.isAuthorized = success

                if success {
                    UserDefaults.standard.set(true, forKey: self?.healthConnectedStorageKey ?? "health_connected_v1")
                    self?.authorizationError = nil
                    self?.refreshEnergy(around: Date())
                    self?.refreshSteps(around: Date())
                    self?.refreshBodyWeights()
                    self?.startObservingChanges()
                    self?.flushPendingBodyWeights()
                    self?.dietaryPermissionRevision &+= 1
                } else {
                    self?.authorizationError = LanguageStore.localizedString("health.access_denied_data_local")
                }
                completion?(success)
            }
        }
    }

    /// Existing Health connections need one additional permission sheet after
    /// an update. A previous denial is respected and never re-prompted here.
    @discardableResult
    func requestMissingMicronutrientAuthorization() -> Bool {
        guard isAuthorized, isHealthDataAvailable, !micronutrientAuthorizationInFlight,
              micronutrientTypes.contains(where: { healthStore.authorizationStatus(for: $0.1) == .notDetermined }) else { return false }
        micronutrientAuthorizationInFlight = true
        requestAuthorization { [weak self] _ in self?.micronutrientAuthorizationInFlight = false }
        return true
    }

    func saveBodyWeight(id: UUID, kilograms: Double, date: Date) {
        guard kilograms.isFinite, kilograms > 0 else { return }
        var pending = pendingBodyWeights()
        pending.removeAll { $0.id == id }
        pending.append(PendingBodyWeight(id: id, kilograms: kilograms, date: date))
        storePendingBodyWeights(pending)
        flushPendingBodyWeights()
    }

    private func flushPendingBodyWeights() {
        guard isHealthDataAvailable, isAuthorized,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              healthStore.authorizationStatus(for: type) == .sharingAuthorized else { return }
        for item in pendingBodyWeights() { replaceBodyWeight(item, type: type) }
    }

    private func replaceBodyWeight(_ item: PendingBodyWeight, type: HKQuantityType) {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: bodyWeightMetadataKey, allowedValues: [item.id.uuidString])
        healthStore.deleteObjects(of: type, predicate: predicate) { [weak self] _, _, deleteError in
            guard let self else { return }
            if let deleteError {
                DispatchQueue.main.async {
                    self.lastWeightSyncMessage = LanguageStore.formattedString("health.weight_sync_failed", arguments: [deleteError.localizedDescription])
                }
                return
            }
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: item.kilograms),
                start: item.date,
                end: item.date,
                metadata: [self.bodyWeightMetadataKey: item.id.uuidString]
            )
            self.healthStore.save(sample) { success, error in
                DispatchQueue.main.async {
                    if success {
                        var pending = self.pendingBodyWeights()
                        pending.removeAll { $0.id == item.id }
                        self.storePendingBodyWeights(pending)
                        self.lastWeightSyncMessage = LanguageStore.localizedString("health.weight_synced")
                        self.refreshBodyWeights(force: true)
                    } else {
                        self.lastWeightSyncMessage = LanguageStore.formattedString("health.weight_sync_failed", arguments: [error?.localizedDescription ?? LanguageStore.localizedString("health.check_permission")])
                    }
                }
            }
        }
    }

    private func pendingBodyWeights() -> [PendingBodyWeight] {
        guard let data = UserDefaults.standard.data(forKey: pendingBodyWeightsStorageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingBodyWeight].self, from: data)) ?? []
    }

    private func storePendingBodyWeights(_ values: [PendingBodyWeight]) {
        if values.isEmpty {
            UserDefaults.standard.removeObject(forKey: pendingBodyWeightsStorageKey)
        } else if let data = try? JSONEncoder().encode(values) {
            UserDefaults.standard.set(data, forKey: pendingBodyWeightsStorageKey)
        }
    }

    func fetchActiveEnergyToday() {
        refreshEnergy(around: Date())
    }

    func fetchActiveEnergyYesterday() {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else { return }
        refreshEnergy(for: yesterday)
    }

    func fetchActiveEnergy(for date: Date, completion: @escaping (Double) -> Void) {
        fetchEnergy(type: activeEnergyType, for: date, useHealthKitSourceMerge: true, completion: completion)
    }

    func energy(for date: Date) -> DailyEnergy? { dailyEnergy[dayKey(for: date)] }
    func steps(for date: Date) -> Int { dailySteps[dayKey(for: date)] ?? 0 }

    func refreshSteps(around date: Date, force: Bool = false) {
        refreshSteps(for: date, force: force)
        if let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) {
            refreshSteps(for: previous, force: force)
        }
    }

    func refreshSteps(for date: Date, force: Bool = false) {
        guard isAuthorized, let stepCountType else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let key = dayKey(for: start)
        guard !stepRefreshesInFlight.contains(key) else { return }
        if !force, let last = lastStepRefreshAt[key], Date().timeIntervalSince(last) < refreshThrottle { return }
        stepRefreshesInFlight.insert(key)
        lastStepRefreshAt[key] = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let query = HKStatisticsQuery(
            quantityType: stepCountType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, error in
            let count = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            DispatchQueue.main.async {
                guard let self else { return }
                self.stepRefreshesInFlight.remove(key)
                guard error == nil else { self.lastStepRefreshAt[key] = nil; return }
                let normalized = max(0, count)
                guard self.dailySteps[key] != normalized else { return }
                self.dailySteps[key] = normalized
                if let data = try? JSONEncoder().encode(self.dailySteps) {
                    UserDefaults.standard.set(data, forKey: self.stepsStorageKey)
                }
            }
        }
        healthStore.execute(query)
    }

    /// Loads every body-mass sample available to Hyse and caches it locally so
    /// the graph is populated immediately on the next launch.
    func refreshBodyWeights(force: Bool = false) {
        guard isAuthorized,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        guard !bodyWeightRefreshInFlight else { return }
        if !force, let lastBodyWeightRefreshAt,
           Date().timeIntervalSince(lastBodyWeightRefreshAt) < refreshThrottle { return }
        bodyWeightRefreshInFlight = true
        lastBodyWeightRefreshAt = Date()

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, error in
            let metadataKey = self?.bodyWeightMetadataKey ?? "HyseBodyWeightID"
            let measurements = (samples as? [HKQuantitySample] ?? []).map { sample in
                let metadataID = sample.metadata?[metadataKey] as? String
                return BodyMeasurement(
                    id: metadataID.flatMap(UUID.init(uuidString:)) ?? sample.uuid,
                    date: sample.startDate,
                    weightKilograms: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                    bodyFatPercentage: nil,
                    centimeters: [:],
                    source: sample.sourceRevision.source.name,
                    updatedAt: sample.endDate
                )
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.bodyWeightRefreshInFlight = false
                guard error == nil else { self.lastBodyWeightRefreshAt = nil; return }
                guard self.bodyWeights != measurements else { return }
                self.bodyWeights = measurements
                if let data = try? JSONEncoder().encode(measurements) {
                    UserDefaults.standard.set(data, forKey: self.bodyWeightStorageKey)
                }
            }
        }
        healthStore.execute(query)
    }

    func refreshEnergy(around date: Date, force: Bool = false) {
        guard isAuthorized else { return }
        refreshEnergy(for: date, force: force)
        if let previous = Calendar.current.date(byAdding: .day, value: -1, to: date) { refreshEnergy(for: previous, force: force) }
    }

    func refreshEnergy(for date: Date, force: Bool = false) {
        guard isAuthorized else { return }
        let key = dayKey(for: date)
        guard !energyRefreshesInFlight.contains(key) else { return }
        if !force, let last = lastEnergyRefreshAt[key], Date().timeIntervalSince(last) < refreshThrottle { return }
        energyRefreshesInFlight.insert(key)
        lastEnergyRefreshAt[key] = Date()
        let group = DispatchGroup()
        var active: Result<EnergyMeasurement, Error>?
        var resting: Result<EnergyMeasurement, Error>?
        group.enter()
        fetchEnergyResult(type: activeEnergyType, for: date, useHealthKitSourceMerge: true) { active = $0; group.leave() }
        group.enter()
        fetchRestingEnergyResult(type: restingEnergyType, for: date) { resting = $0; group.leave() }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.energyRefreshesInFlight.remove(key)
            let cached = self.energy(for: date)
            let activeValue: EnergyMeasurement? = if case .success(let value) = active { value } else { nil }
            let restingValue: EnergyMeasurement? = if case .success(let value) = resting { value } else { nil }
            guard activeValue != nil || restingValue != nil else { self.lastEnergyRefreshAt[key] = nil; return }
            self.storeEnergy(
                date: date,
                resting: restingValue?.value ?? cached?.resting ?? 0,
                active: activeValue?.value ?? cached?.active ?? 0,
                restingMeasurement: restingValue,
                cached: cached
            )
        }
    }

    private func fetchEnergy(
        type: HKQuantityType?,
        for date: Date,
        useHealthKitSourceMerge: Bool = false,
        completion: @escaping (Double) -> Void
    ) {
        fetchEnergyResult(type: type, for: date, useHealthKitSourceMerge: useHealthKitSourceMerge) { result in
            completion((try? result.get().value) ?? 0)
        }
    }

    private func fetchEnergyResult(
        type: HKQuantityType?,
        for date: Date,
        useHealthKitSourceMerge: Bool = false,
        completion: @escaping (Result<EnergyMeasurement, Error>) -> Void
    ) {
        guard let type else { completion(.success(EnergyMeasurement(value: 0, sourceName: "Apple Health", sourceCount: 0, selectionStrategy: "none"))); return }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion(.failure(URLError(.cannotParseResponse)))
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let query = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            // Active energy must use HealthKit's own source merge. This includes
            // samples entered manually in Health while letting HealthKit resolve
            // overlaps between Apple Watch, iPhone and third-party sources.
            options: useHealthKitSourceMerge ? .cumulativeSum : [.cumulativeSum, .separateBySource]
        ) { _, result, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let measurement: EnergyMeasurement
            if useHealthKitSourceMerge {
                measurement = EnergyMeasurement(
                    value: result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
                    sourceName: "Apple Health",
                    sourceCount: result?.sources?.count ?? 0,
                    selectionStrategy: "healthKitMerged"
                )
            } else {
                let sources = result?.sources ?? []
                let measurements = sources.compactMap { source -> (HKSource, Double)? in
                    guard let quantity = result?.sumQuantity(for: source) else { return nil }
                    return (source, quantity.doubleValue(for: .kilocalorie()))
                }
                // Keep the conservative source selection for resting energy,
                // where overlapping full-day estimates must not be added.
                let selected = measurements.max { $0.1 < $1.1 }
                measurement = EnergyMeasurement(
                    value: selected?.1 ?? 0,
                    sourceName: selected?.0.name ?? "Apple Health",
                    sourceCount: measurements.count,
                    selectionStrategy: measurements.count > 1 ? "highestDailyTotal" : "singleSource"
                )
            }
            DispatchQueue.main.async {
                completion(.success(measurement))
            }
        }

        healthStore.execute(query)
    }

    private func fetchRestingEnergyResult(
        type: HKQuantityType?,
        for date: Date,
        completion: @escaping (Result<EnergyMeasurement, Error>) -> Void
    ) {
        guard let type else {
            completion(.success(EnergyMeasurement(value: 0, sourceName: "Apple Health", sourceCount: 0, selectionStrategy: "none")))
            return
        }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            completion(.failure(URLError(.cannotParseResponse)))
            return
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        let group = DispatchGroup()
        var statistics: HKStatistics?
        var quantitySamples: [HKQuantitySample] = []
        var queryError: Error?

        group.enter()
        let statisticsQuery = HKStatisticsQuery(
            quantityType: type,
            quantitySamplePredicate: predicate,
            options: [.cumulativeSum, .separateBySource]
        ) { _, result, error in
            statistics = result
            if let error { queryError = error }
            group.leave()
        }

        group.enter()
        let sampleQuery = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            quantitySamples = (samples as? [HKQuantitySample]) ?? []
            if let error { queryError = error }
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            if let queryError {
                DispatchQueue.main.async { completion(.failure(queryError)) }
                return
            }

            let sources = statistics?.sources ?? []
            var manualBySource: [String: Double] = [:]
            var sourceNames: [String: String] = [:]
            for sample in quantitySamples where (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true {
                let sourceID = sample.sourceRevision.source.bundleIdentifier
                manualBySource[sourceID, default: 0] += sample.quantity.doubleValue(for: .kilocalorie())
                sourceNames[sourceID] = sample.sourceRevision.source.name
            }

            let automaticMeasurements = sources.compactMap { source -> (id: String, name: String, value: Double)? in
                guard let quantity = statistics?.sumQuantity(for: source) else { return nil }
                let sourceID = source.bundleIdentifier
                sourceNames[sourceID] = source.name
                let total = quantity.doubleValue(for: .kilocalorie())
                return (sourceID, source.name, max(0, total - manualBySource[sourceID, default: 0]))
            }
            let selectedAutomatic = automaticMeasurements.max { $0.value < $1.value }
            let manualTotal = manualBySource.values.reduce(0, +)
            let combinedValue = (selectedAutomatic?.value ?? 0) + manualTotal
            let contributingSourceIDs = Set(
                automaticMeasurements.filter { $0.value > 0 }.map(\.id) + manualBySource.filter { $0.value > 0 }.map(\.key)
            )
            let sourceName = selectedAutomatic.flatMap { $0.value > 0 ? $0.name : nil }
                ?? manualBySource.keys.first.flatMap { sourceNames[$0] }
                ?? "Apple Health"
            let strategy = manualTotal > 0
                ? "highestAutomaticPlusManualEntries"
                : (automaticMeasurements.count > 1 ? "highestDailyTotal" : "singleSource")
            let measurement = EnergyMeasurement(
                value: combinedValue,
                sourceName: sourceName,
                sourceCount: contributingSourceIDs.count,
                selectionStrategy: strategy
            )
            DispatchQueue.main.async { completion(.success(measurement)) }
        }

        healthStore.execute(statisticsQuery)
        healthStore.execute(sampleQuery)
    }

    private func storeEnergy(date: Date, resting: Double, active: Double, restingMeasurement: EnergyMeasurement?, cached: DailyEnergy?) {
        let start = Calendar.current.startOfDay(for: date)
        dailyEnergy[dayKey(for: start)] = DailyEnergy(
            date: start,
            resting: resting,
            active: active,
            updatedAt: Date(),
            sourceName: restingMeasurement?.sourceName ?? cached?.sourceName ?? "Apple Health",
            sourceCount: restingMeasurement?.sourceCount ?? cached?.sourceCount,
            sourceSelectionStrategy: restingMeasurement?.selectionStrategy ?? cached?.sourceSelectionStrategy
        )
        if let data = try? JSONEncoder().encode(dailyEnergy) { UserDefaults.standard.set(data, forKey: energyStorageKey) }
    }

    private func dayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func startObservingChanges() {
        guard let activeType = activeEnergyType else { return }

        let activeQuery = HKObserverQuery(sampleType: activeType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil { DispatchQueue.main.async { self?.refreshEnergy(around: Date(), force: true) } }
            completionHandler()
        }

        healthStore.execute(activeQuery)
        healthStore.enableBackgroundDelivery(for: activeType, frequency: .immediate) { _, _ in }

        if let restingType = restingEnergyType {
            let restingQuery = HKObserverQuery(sampleType: restingType, predicate: nil) { [weak self] _, completionHandler, error in
                if error == nil { DispatchQueue.main.async { self?.refreshEnergy(around: Date(), force: true) } }
                completionHandler()
            }
            healthStore.execute(restingQuery)
            healthStore.enableBackgroundDelivery(for: restingType, frequency: .daily) { _, _ in }
        }

        if let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let bodyMassQuery = HKObserverQuery(sampleType: bodyMassType, predicate: nil) { [weak self] _, completionHandler, error in
                if error == nil { DispatchQueue.main.async { self?.refreshBodyWeights(force: true) } }
                completionHandler()
            }
            healthStore.execute(bodyMassQuery)
            healthStore.enableBackgroundDelivery(for: bodyMassType, frequency: .immediate) { _, _ in }
        }

        if let stepCountType {
            let stepsQuery = HKObserverQuery(sampleType: stepCountType, predicate: nil) { [weak self] _, completionHandler, error in
                if error == nil { DispatchQueue.main.async { self?.refreshSteps(around: Date(), force: true) } }
                completionHandler()
            }
            healthStore.execute(stepsQuery)
            healthStore.enableBackgroundDelivery(for: stepCountType, frequency: .immediate) { _, _ in }
        }
    }

    // MARK: - HealthKit Ernährungsexport
    func saveDietaryEntry(_ entry: CalorieEntry) {
        guard isHealthDataAvailable else { return }
        enqueueDietaryOperation { [weak self] done in
            guard let self else { done(); return }
            self.saveDietarySamples(self.dietarySamples(for: entry), completion: { _ in done() })
        }
    }

    func deleteDietaryEntry(id: UUID, completion: (() -> Void)? = nil) {
        guard isHealthDataAvailable else {
            completion?()
            return
        }

        enqueueDietaryOperation { [weak self] done in
            guard let self else { completion?(); done(); return }
            self.deleteDietarySamples(id: id, types: self.dietaryEntryTypes) { _ in
                completion?()
                done()
            }
        }
    }

    func updateDietaryEntry(_ entry: CalorieEntry) {
        guard isHealthDataAvailable else { return }
        enqueueDietaryOperation { [weak self] done in
            guard let self else { done(); return }
            self.deleteDietarySamples(id: entry.id, types: self.dietaryEntryTypes) { deleted in
                guard deleted else { done(); return }
                self.saveDietarySamples(self.dietarySamples(for: entry), completion: { _ in done() })
            }
        }
    }

    /// Newly analyzed foods and server refreshes can change several older
    /// diary entries at once without changing their calories or macros.
    func reconcileDietaryMicronutrients(entries: [CalorieEntry]) {
        guard isHealthDataAvailable, isAuthorized, !entries.isEmpty,
              micronutrientTypes.contains(where: { healthStore.authorizationStatus(for: $0.1) == .sharingAuthorized }) else { return }
        enqueueDietaryOperation { [weak self] done in
            guard let self else { done(); return }
            self.backfillMicronutrientChunk(entries, types: self.micronutrientTypes.map(\.1), offset: 0) { _ in done() }
        }
    }

    /// Export existing diary profiles once for each granted nutrient type.
    /// Replacing samples by their stable entry IDs makes an interrupted pass
    /// safe to repeat without doubling Health's daily totals.
    func backfillDietaryMicronutrients(entries: [CalorieEntry], scopeID: String) {
        guard isHealthDataAvailable, isAuthorized else { return }
        DispatchQueue.main.async {
            let key = self.micronutrientBackfillKeyPrefix + scopeID
            guard !self.pendingMicronutrientBackfills.contains(key) else { return }
            let recorded = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
            let authorized = self.micronutrientTypes.map(\.1).filter {
                self.healthStore.authorizationStatus(for: $0) == .sharingAuthorized
            }
            // A permission revoked since the previous run must be reconciled
            // again if the user later grants it back.
            let completed = recorded.intersection(Set(authorized.map(\.identifier)))
            if completed != recorded { UserDefaults.standard.set(Array(completed).sorted(), forKey: key) }
            let missing = authorized.filter { !completed.contains($0.identifier) }
            guard !missing.isEmpty else { return }
            self.pendingMicronutrientBackfills.insert(key)
            let eligible = entries.filter { $0.micronutrients?.isEmpty == false }
            self.enqueueDietaryOperation { [weak self] done in
                guard let self else { done(); return }
                self.backfillMicronutrientChunk(eligible, types: missing, offset: 0) { success in
                    DispatchQueue.main.async {
                        if success {
                            let stillAuthorized = missing.filter { self.healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
                            let updated = completed.union(stillAuthorized.map(\.identifier))
                            UserDefaults.standard.set(Array(updated).sorted(), forKey: key)
                        }
                        self.pendingMicronutrientBackfills.remove(key)
                        done()
                    }
                }
            }
        }
    }

    private func backfillMicronutrientChunk(
        _ entries: [CalorieEntry], types: [HKQuantityType], offset: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard offset < entries.count else { completion(true); return }
        let chunk = Array(entries[offset..<min(offset + 100, entries.count)])
        deleteDietarySamples(ids: chunk.map(\.id), types: types) { [weak self] deleted in
            guard let self, deleted else { completion(false); return }
            let samples = chunk.flatMap { self.micronutrientSamples(for: $0, limitedTo: types) }
            self.saveDietarySampleBatches(samples, offset: 0) { saved in
                guard saved else { completion(false); return }
                self.backfillMicronutrientChunk(entries, types: types, offset: offset + chunk.count, completion: completion)
            }
        }
    }

    private func saveDietarySampleBatches(_ samples: [HKQuantitySample], offset: Int, completion: @escaping (Bool) -> Void) {
        guard offset < samples.count else { completion(true); return }
        let batch = Array(samples[offset..<min(offset + 200, samples.count)])
        saveDietarySamples(batch) { [weak self] saved in
            guard let self, saved else { completion(false); return }
            self.saveDietarySampleBatches(samples, offset: offset + batch.count, completion: completion)
        }
    }

    private var dietaryEntryTypes: [HKQuantityType] {
        let macros: [HKQuantityType?] = [
            .quantityType(forIdentifier: .dietaryEnergyConsumed),
            .quantityType(forIdentifier: .dietaryCarbohydrates),
            .quantityType(forIdentifier: .dietaryProtein),
            .quantityType(forIdentifier: .dietaryFatTotal),
            .quantityType(forIdentifier: .dietarySugar),
            .quantityType(forIdentifier: .dietaryFiber),
            .quantityType(forIdentifier: .dietaryFatSaturated)
        ]
        return macros.compactMap { $0 } + micronutrientTypes.map(\.1)
    }

    private func dietarySamples(for entry: CalorieEntry) -> [HKQuantitySample] {
        let macros: [(HKQuantityTypeIdentifier, Double, HKUnit)] = [
            (.dietaryEnergyConsumed, entry.kcal, .kilocalorie()),
            (.dietaryCarbohydrates, entry.carbs, .gram()),
            (.dietaryProtein, entry.protein, .gram()),
            (.dietaryFatTotal, entry.fat, .gram()),
            (.dietarySugar, entry.sugar, .gram()),
            (.dietaryFiber, entry.fiber, .gram()),
            (.dietaryFatSaturated, entry.saturatedFat, .gram())
        ]
        let metadata = dietaryMetadata(for: entry)
        let macroSamples = macros.compactMap { identifier, value, unit -> HKQuantitySample? in
            guard value.isFinite, value > 0,
                  let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                    start: entry.date, end: entry.date, metadata: metadata)
        }
        return macroSamples + micronutrientSamples(for: entry)
    }

    private func micronutrientSamples(for entry: CalorieEntry, limitedTo types: [HKQuantityType]? = nil) -> [HKQuantitySample] {
        let allowedIdentifiers = types.map { Set($0.map(\.identifier)) }
        return micronutrientTypes.compactMap { nutrient, type in
            guard allowedIdentifiers?.contains(type.identifier) ?? true else { return nil }
            let grams: Double
            var metadata = dietaryMetadata(for: entry)
            if let amount = entry.micronutrientAmount(nutrient) {
                grams = amount / nutrient.gramsToDisplayUnit
                metadata["HyseMicronutrientSource"] = entry.micronutrients?.source.rawValue
            } else if nutrient == .sodium {
                grams = entry.salt / 2.5
            } else {
                return nil
            }
            guard grams.isFinite, grams > 0 else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: .gram(), doubleValue: grams),
                                    start: entry.date, end: entry.date, metadata: metadata)
        }
    }

    private func dietaryMetadata(for entry: CalorieEntry) -> [String: Any] {
        [HKMetadataKeyFoodType: entry.name, calorieEntryMetadataKey: entry.id.uuidString]
    }

    private func enqueueDietaryOperation(_ operation: @escaping (@escaping () -> Void) -> Void) {
        DispatchQueue.main.async {
            self.dietaryOperations.append(operation)
            self.runNextDietaryOperation()
        }
    }

    private func runNextDietaryOperation() {
        guard !dietaryOperationRunning, !dietaryOperations.isEmpty else { return }
        dietaryOperationRunning = true
        let operation = dietaryOperations.removeFirst()
        operation { [weak self] in
            DispatchQueue.main.async {
                self?.dietaryOperationRunning = false
                self?.runNextDietaryOperation()
            }
        }
    }

    private func saveDietarySamples(_ samples: [HKQuantitySample], completion: @escaping (Bool) -> Void) {
        let authorized = samples.filter { healthStore.authorizationStatus(for: $0.quantityType) == .sharingAuthorized }
        guard !authorized.isEmpty else { completion(true); return }
        healthStore.save(authorized) { success, error in
            if let error { print("HealthKit dietary save failed: \(error.localizedDescription)") }
            completion(success)
        }
    }

    private func deleteDietarySamples(id: UUID, types: [HKQuantityType], completion: @escaping (Bool) -> Void) {
        deleteDietarySamples(ids: [id], types: types, completion: completion)
    }

    private func deleteDietarySamples(ids: [UUID], types: [HKQuantityType], completion: @escaping (Bool) -> Void) {
        guard !ids.isEmpty else { completion(true); return }
        let authorized = types.filter { healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
        guard !authorized.isEmpty else { completion(true); return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: calorieEntryMetadataKey, allowedValues: ids.map(\.uuidString))
        let group = DispatchGroup()
        let lock = NSLock()
        var succeeded = true
        for type in authorized {
            group.enter()
            healthStore.deleteObjects(of: type, predicate: predicate) { deleted, _, error in
                if !deleted || error != nil {
                    lock.lock()
                    succeeded = false
                    lock.unlock()
                    print("HealthKit dietary delete failed: \(error?.localizedDescription ?? "unknown error")")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(succeeded) }
    }

    func syncWaterIntake(totalMilliliters: Double, date: Date = Date()) {
        guard isHealthDataAvailable else {
            lastWaterSyncMessage = LanguageStore.localizedString("health.water_unavailable_local")
            return
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            lastWaterSyncMessage = LanguageStore.localizedString("health.water_unsupported")
            return
        }
        guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
            lastWaterSyncMessage = LanguageStore.localizedString("health.water_access_missing")
            return
        }

        let dayKey = waterDayKey(for: date)
        let predicate = HKQuery.predicateForObjects(withMetadataKey: waterDayMetadataKey, allowedValues: [dayKey])
        healthStore.deleteObjects(of: type, predicate: predicate) { [weak self] _, _, deleteError in
            guard let self else { return }
            if let deleteError {
                DispatchQueue.main.async {
                    self.lastWaterSyncMessage = LanguageStore.formattedString("health.update_failed", arguments: [deleteError.localizedDescription])
                }
                return
            }
            guard totalMilliliters > 0 else {
                DispatchQueue.main.async { self.lastWaterSyncMessage = LanguageStore.localizedString("health.water_updated") }
                return
            }
            let sampleDate = self.dateWithCurrentTime(on: date)
            let sample = HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: totalMilliliters),
                start: sampleDate,
                end: sampleDate,
                metadata: [self.waterDayMetadataKey: dayKey]
            )
            self.healthStore.save(sample) { success, error in
                DispatchQueue.main.async {
                    self.lastWaterSyncMessage = success
                        ? LanguageStore.localizedString("health.synced")
                        : LanguageStore.formattedString("health.sync_failed", arguments: [error?.localizedDescription ?? LanguageStore.localizedString("health.check_permission")])
                }
            }
        }
    }

    func saveWaterIntake(milliliters: Double, date: Date = Date()) {
        syncWaterIntake(totalMilliliters: milliliters, date: date)
    }

    private func waterDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func dateWithCurrentTime(on date: Date) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
    }
}
