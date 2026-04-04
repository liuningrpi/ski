#if os(iOS)
import Foundation
import Combine
import WatchConnectivity
import os.log

/// Receives live heart-rate samples streamed from Apple Watch.
final class WatchHeartRateReceiver: NSObject, ObservableObject {

    static let shared = WatchHeartRateReceiver()
    private static let logger = Logger(subsystem: "com.nliu.SkiTracker", category: "WatchHeartRateReceiver")

    @Published private(set) var liveStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var connectionStatus: String = "idle"

    private var values: [Double] = []
    private var activeSessionId: String?
    private var activeStartedAt: Date?

    private func publishOnMain(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async(execute: updates)
        }
    }

    private override init() {
        super.init()
        activateSession()
    }

    var hasRecentSample: Bool {
        guard let lastSampleAt else { return false }
        return Date().timeIntervalSince(lastSampleAt) <= 20
    }

    var isWatchAppInstalled: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.isPaired && session.isWatchAppInstalled
    }

    func beginLiveSession(sessionId: String, startedAt: Date) {
        publishOnMain {
            self.activeSessionId = sessionId
            self.activeStartedAt = startedAt
            self.values.removeAll()
            self.lastSampleAt = nil
            self.liveStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
            self.connectionStatus = "starting"
        }

        Self.logger.log("Begin live HR session id=\(sessionId, privacy: .public)")

        let command = WatchHeartRateCommandMessage(
            type: .startLiveHeartRate,
            sessionId: sessionId,
            startedAt: startedAt
        )
        send(command: command)
    }

    func endLiveSession() {
        if let activeSessionId {
            let command = WatchHeartRateCommandMessage(
                type: .stopLiveHeartRate,
                sessionId: activeSessionId,
                startedAt: nil
            )
            send(command: command)
        }
        Self.logger.log("End live HR session id=\(self.activeSessionId ?? "-", privacy: .public)")
        publishOnMain {
            self.activeSessionId = nil
            self.activeStartedAt = nil
            self.values.removeAll()
            self.lastSampleAt = nil
            self.liveStats = HeartRateStats(maxBPM: nil, avgBPM: nil)
            self.connectionStatus = "idle"
        }
    }

    private func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        publishOnMain {
            self.connectionStatus = "activating"
        }
        session.activate()
    }

    private func send(command: WatchHeartRateCommandMessage) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        if session.activationState != .activated {
            session.activate()
        }

        guard session.isPaired else {
            publishOnMain {
                self.connectionStatus = "watch_not_paired"
            }
            Self.logger.error("Cannot send command: Apple Watch is not paired")
            return
        }

        guard session.isWatchAppInstalled else {
            publishOnMain {
                self.connectionStatus = "watch_app_missing"
            }
            Self.logger.error("Cannot send command: Watch app not installed")
            return
        }

        let payload = command.dictionary
        if session.isReachable {
            publishOnMain {
                self.connectionStatus = "reachable"
            }
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            publishOnMain {
                self.connectionStatus = "background_delivery"
            }
            try? session.updateApplicationContext(payload)
            session.transferUserInfo(payload)
        }
    }

    private func ingest(sample: WatchHeartRateSampleMessage) {
        guard sample.bpm.isFinite, sample.bpm > 0 else { return }

        guard let activeStartedAt else { return }

        // Allow slight skew between phone/watch clocks.
        let earliest = activeStartedAt.addingTimeInterval(-180)
        guard sample.timestamp >= earliest else { return }

        if let activeSessionId,
           let incomingSessionId = sample.sessionId,
           incomingSessionId != activeSessionId {
            return
        }

        values.append(sample.bpm)
        let maxBPM = values.max()
        let avgBPM = values.reduce(0, +) / Double(values.count)

        Self.logger.log("Ingest HR sample bpm=\(sample.bpm, privacy: .public) count=\(self.values.count, privacy: .public)")
        publishOnMain {
            self.lastSampleAt = sample.timestamp
            self.liveStats = HeartRateStats(maxBPM: maxBPM, avgBPM: avgBPM)
            self.connectionStatus = "receiving_samples"
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchHeartRateReceiver: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            publishOnMain {
                self.connectionStatus = "activation_error"
            }
            Self.logger.error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        publishOnMain {
            self.connectionStatus = "activated_\(activationState.rawValue)"
        }
        Self.logger.log("WCSession activated state=\(activationState.rawValue, privacy: .public) paired=\(session.isPaired, privacy: .public) watchInstalled=\(session.isWatchAppInstalled, privacy: .public)")
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        publishOnMain {
            self.connectionStatus = "reactivating"
        }
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let sample = WatchHeartRateSampleMessage(dictionary: message) {
            ingest(sample: sample)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if let sample = WatchHeartRateSampleMessage(dictionary: applicationContext) {
            ingest(sample: sample)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let sample = WatchHeartRateSampleMessage(dictionary: userInfo) {
            ingest(sample: sample)
        }
    }
}
#endif
