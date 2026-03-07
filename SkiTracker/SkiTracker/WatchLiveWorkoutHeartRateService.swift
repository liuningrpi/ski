#if os(watchOS)
import Foundation
import HealthKit
import WatchConnectivity
import os.log

/// Watch-side authoritative live HR stream powered by HKLiveWorkoutBuilder.
final class WatchLiveWorkoutHeartRateService: NSObject {

    static let shared = WatchLiveWorkoutHeartRateService()
    private static let logger = Logger(subsystem: "com.nliu.SkiTracker", category: "WatchLiveWorkoutHeartRateService")

    private let healthStore = HKHealthStore()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private let workoutType = HKObjectType.workoutType()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    private var currentSessionId: String?
    private var didRequestAuthorization = false

    private override init() {
        super.init()
        activateWatchConnectivity()
    }

    static func bootstrap() {
        _ = Self.shared
    }

    func activateWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        Self.logger.log("Activating WatchConnectivity session")
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType else { return false }

        if didRequestAuthorization {
            let status = healthStore.authorizationStatus(for: heartRateType)
            return status == .sharingAuthorized
        }
        didRequestAuthorization = true

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { success, _ in
                Self.logger.log("HealthKit authorization success=\(success, privacy: .public)")
                continuation.resume(returning: success)
            }
        }
    }

    func startLiveSession(sessionId: String, startedAt: Date?) {
        Task {
            Self.logger.log("Start live HR request sessionId=\(sessionId, privacy: .public)")
            let authorized = await requestAuthorizationIfNeeded()
            guard authorized else {
                Self.logger.error("HealthKit authorization not granted")
                return
            }

            let startDate = startedAt ?? Date()
            let config = HKWorkoutConfiguration()
            config.activityType = .downhillSkiing
            config.locationType = .outdoor

            do {
                if workoutSession != nil || workoutBuilder != nil {
                    stopLiveSession()
                }

                let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
                let builder = session.associatedWorkoutBuilder()

                session.delegate = self
                builder.delegate = self
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

                currentSessionId = sessionId
                workoutSession = session
                workoutBuilder = builder

                session.startActivity(with: startDate)
                try await beginCollection(builder: builder, startDate: startDate)
                Self.logger.log("Live HR collection started")
            } catch {
                Self.logger.error("Failed to start live HR session: \(error.localizedDescription, privacy: .public)")
                stopLiveSession()
            }
        }
    }

    func stopLiveSession() {
        guard let workoutSession, let workoutBuilder else {
            currentSessionId = nil
            return
        }

        workoutSession.end()
        workoutBuilder.endCollection(withEnd: Date()) { [weak self] _, _ in
            workoutBuilder.finishWorkout { _, _ in
                self?.workoutSession = nil
                self?.workoutBuilder = nil
                self?.currentSessionId = nil
                Self.logger.log("Live HR session stopped")
            }
        }
    }

    private func beginCollection(builder: HKLiveWorkoutBuilder, startDate: Date) async throws {
        try await withCheckedThrowingContinuation { continuation in
            builder.beginCollection(withStart: startDate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard success else {
                    continuation.resume(throwing: NSError(domain: "WatchLiveWorkoutHeartRateService", code: 1))
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private func publishHeartRateSample(bpm: Double, at timestamp: Date) {
        guard bpm.isFinite, bpm > 0 else { return }

        var payload: [String: Any] = [
            WatchHeartRateBridgeKeys.type: WatchHeartRateBridgeType.liveHeartRateSample.rawValue,
            WatchHeartRateBridgeKeys.bpm: bpm,
            WatchHeartRateBridgeKeys.timestamp: timestamp.timeIntervalSince1970
        ]
        if let currentSessionId {
            payload[WatchHeartRateBridgeKeys.sessionId] = currentSessionId
        }

        guard WCSession.isSupported() else { return }
        let wcSession = WCSession.default
        do {
            try wcSession.updateApplicationContext(payload)
        } catch {
            Self.logger.error("Failed to update application context: \(error.localizedDescription, privacy: .public)")
        }
        if wcSession.isReachable {
            wcSession.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        Self.logger.log("Published HR sample bpm=\(bpm, privacy: .public) reachable=\(wcSession.isReachable, privacy: .public)")
    }

    private func handleIncoming(message: [String: Any]) {
        guard let typeRaw = message[WatchHeartRateBridgeKeys.type] as? String,
              let type = WatchHeartRateBridgeType(rawValue: typeRaw) else {
            return
        }

        switch type {
        case .startLiveHeartRate:
            let sessionId = (message[WatchHeartRateBridgeKeys.sessionId] as? String) ?? UUID().uuidString
            let startTime = (message[WatchHeartRateBridgeKeys.startedAt] as? TimeInterval)
                .map(Date.init(timeIntervalSince1970:)) ?? Date()
            startLiveSession(sessionId: sessionId, startedAt: startTime)
        case .stopLiveHeartRate:
            stopLiveSession()
        case .liveHeartRateSample:
            break
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchLiveWorkoutHeartRateService: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Self.logger.log("Workout session state changed from=\(fromState.rawValue, privacy: .public) to=\(toState.rawValue, privacy: .public)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.logger.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
        stopLiveSession()
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchLiveWorkoutHeartRateService: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let heartRateType else { return }
        guard collectedTypes.contains(heartRateType) else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let stats = workoutBuilder.statistics(for: heartRateType),
              let quantity = stats.mostRecentQuantity() else {
            return
        }
        let bpm = quantity.doubleValue(for: unit)
        publishHeartRateSample(bpm: bpm, at: Date())
    }
}

// MARK: - WCSessionDelegate

extension WatchLiveWorkoutHeartRateService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            Self.logger.error("Watch WC activation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        Self.logger.log("Watch WC activated state=\(activationState.rawValue, privacy: .public) reachable=\(session.isReachable, privacy: .public)")
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncoming(message: message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncoming(message: applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleIncoming(message: userInfo)
    }
}
#endif
