import Foundation
import HealthKit

struct HeartRateStats {
    let maxBPM: Double?
    let avgBPM: Double?
}

final class HeartRateService {

    static let shared = HeartRateService()

    private let healthStore = HKHealthStore()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private var hasRequestedAuthorization = false
    private let liveQueryQueue = DispatchQueue(label: "HeartRateService.liveQuery")
    private var liveQuery: HKAnchoredObjectQuery?
    private var liveAnchor: HKQueryAnchor?
    private var liveSessionStart: Date?
    private var liveValues: [Double] = []

    private init() {}

    func startLiveUpdates(start: Date, onUpdate: @escaping (HeartRateStats) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType else {
            Task { @MainActor in
                onUpdate(HeartRateStats(maxBPM: nil, avgBPM: nil))
            }
            return
        }

        Task {
            let authorized = await requestAuthorizationIfNeeded(for: heartRateType)
            guard authorized else {
                await MainActor.run {
                    onUpdate(HeartRateStats(maxBPM: nil, avgBPM: nil))
                }
                return
            }

            liveQueryQueue.sync {
                liveValues.removeAll()
                liveAnchor = nil
                liveSessionStart = start
            }

            // Start slightly earlier to tolerate watch/iPhone sample timestamp skew.
            let queryStart = start.addingTimeInterval(-180)
            let predicate = HKQuery.predicateForSamples(withStart: queryStart, end: nil, options: [])
            let query = HKAnchoredObjectQuery(
                type: heartRateType,
                predicate: predicate,
                anchor: nil,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, _, newAnchor, _ in
                Task { @MainActor [weak self] in
                    self?.processLiveSamples(samples, newAnchor: newAnchor, onUpdate: onUpdate)
                }
            }

            query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
                Task { @MainActor [weak self] in
                    self?.processLiveSamples(samples, newAnchor: newAnchor, onUpdate: onUpdate)
                }
            }

            liveQueryQueue.sync {
                if let existing = liveQuery {
                    healthStore.stop(existing)
                }
                liveQuery = query
            }

            healthStore.execute(query)
        }
    }

    func stopLiveUpdates() {
        liveQueryQueue.sync {
            if let liveQuery {
                healthStore.stop(liveQuery)
            }
            liveQuery = nil
            liveAnchor = nil
            liveSessionStart = nil
            liveValues.removeAll()
        }
    }

    func fetchStats(start: Date, end: Date) async -> HeartRateStats {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType,
              start <= end else {
            return HeartRateStats(maxBPM: nil, avgBPM: nil)
        }

        let authorized = await requestAuthorizationIfNeeded(for: heartRateType)
        guard authorized else {
            return HeartRateStats(maxBPM: nil, avgBPM: nil)
        }

        return await queryStats(type: heartRateType, start: start, end: end)
    }

    private func requestAuthorizationIfNeeded(for type: HKQuantityType) async -> Bool {
        let status = healthStore.authorizationStatus(for: type)
        if status == .sharingAuthorized {
            return true
        }

        if hasRequestedAuthorization && status != .notDetermined {
            return false
        }

        hasRequestedAuthorization = true

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [type]) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    private func queryStats(type: HKQuantityType, start: Date, end: Date) async -> HeartRateStats {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample], !samples.isEmpty else {
                    continuation.resume(returning: HeartRateStats(maxBPM: nil, avgBPM: nil))
                    return
                }

                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                let values = samples
                    .filter { $0.endDate >= start && $0.startDate <= end }
                    .map { $0.quantity.doubleValue(for: bpmUnit) }
                    .filter { $0.isFinite && $0 > 0 }

                guard !values.isEmpty else {
                    continuation.resume(returning: HeartRateStats(maxBPM: nil, avgBPM: nil))
                    return
                }

                let maxBPM = values.max()
                let avgBPM = values.reduce(0, +) / Double(values.count)
                continuation.resume(returning: HeartRateStats(maxBPM: maxBPM, avgBPM: avgBPM))
            }

            healthStore.execute(query)
        }
    }

    private func processLiveSamples(
        _ samples: [HKSample]?,
        newAnchor: HKQueryAnchor?,
        onUpdate: @escaping (HeartRateStats) -> Void
    ) {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())

        var statsToEmit: HeartRateStats?
        liveQueryQueue.sync {
            liveAnchor = newAnchor
            let sessionStart = liveSessionStart ?? .distantPast
            let bpmValues = (samples as? [HKQuantitySample] ?? [])
                .filter { $0.endDate >= sessionStart }
                .map { $0.quantity.doubleValue(for: bpmUnit) }
                .filter { $0.isFinite && $0 > 0 }
            if !bpmValues.isEmpty {
                liveValues.append(contentsOf: bpmValues)
            }

            guard !liveValues.isEmpty else {
                statsToEmit = HeartRateStats(maxBPM: nil, avgBPM: nil)
                return
            }

            let maxBPM = liveValues.max()
            let avgBPM = liveValues.reduce(0, +) / Double(liveValues.count)
            statsToEmit = HeartRateStats(maxBPM: maxBPM, avgBPM: avgBPM)
        }

        guard let statsToEmit else { return }
        Task { @MainActor in
            onUpdate(statsToEmit)
        }
    }
}
