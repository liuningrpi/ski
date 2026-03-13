import Foundation
import UIKit
import FirebaseFirestore

// MARK: - Log Level

enum LogLevel: String, Codable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

// MARK: - Log Entry

struct LogEntry: Codable {
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    let metadata: [String: String]?
    let deviceInfo: String
    let appVersion: String
    let userId: String?
}

// MARK: - Logging Service

final class LoggingService {

    static let shared = LoggingService()

    private let db = Firestore.firestore()
    private var localLogs: [LogEntry] = []
    private let maxLocalLogs = 100
    private var uploadTimer: Timer?

    // Device & App Info
    private let deviceInfo: String
    private let appVersion: String

    private init() {
        #if targetEnvironment(simulator)
        deviceInfo = "Simulator"
        #else
        deviceInfo = UIDevice.current.model
        #endif

        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        // Start periodic upload timer (every 60 seconds)
        startUploadTimer()
    }

    deinit {
        uploadTimer?.invalidate()
    }

    // MARK: - Public Logging Methods

    func debug(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .debug, category: category, message: message, metadata: metadata)
    }

    func info(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .info, category: category, message: message, metadata: metadata)
    }

    func warning(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .warning, category: category, message: message, metadata: metadata)
    }

    func error(_ message: String, category: String = "General", metadata: [String: String]? = nil) {
        log(level: .error, category: category, message: message, metadata: metadata)
    }

    // MARK: - Specialized Logging

    func logStateChange(from: SkiingState, to: SkiingState, speed: Double, altitude: Double, altitudeRate: Double) {
        let metadata: [String: String] = [
            "fromState": from.rawValue,
            "toState": to.rawValue,
            "speed_ms": String(format: "%.2f", speed),
            "altitude_m": String(format: "%.1f", altitude),
            "altitudeRate_ms": String(format: "%.3f", altitudeRate)
        ]
        info("State changed: \(from.rawValue) -> \(to.rawValue)", category: "Segmentation", metadata: metadata)
    }

    func logRunCompleted(run: RunSegment) {
        let metadata: [String: String] = [
            "runId": run.id.uuidString,
            "duration_s": String(format: "%.0f", run.durationSeconds),
            "distance_m": String(format: "%.0f", run.totalDistanceMeters),
            "maxSpeed_kmh": String(format: "%.1f", run.maxSpeedKmh),
            "avgSpeed_kmh": String(format: "%.1f", run.avgSpeedKmh),
            "elevationDrop_m": String(format: "%.0f", run.elevationDrop),
            "pointCount": "\(run.points.count)"
        ]
        info("Run completed", category: "Runs", metadata: metadata)
    }

    func logSessionStart() {
        info("Session started", category: "Session")
    }

    func logSessionEnd(runCount: Int, liftCount: Int, totalDistance: Double, totalVertical: Double) {
        let metadata: [String: String] = [
            "runCount": "\(runCount)",
            "liftCount": "\(liftCount)",
            "totalDistance_km": String(format: "%.2f", totalDistance),
            "totalVertical_m": String(format: "%.0f", totalVertical)
        ]
        info("Session ended", category: "Session", metadata: metadata)
    }

    func logLocationUpdate(speed: Double, altitude: Double, accuracy: Double, state: SkiingState) {
        let metadata: [String: String] = [
            "speed_ms": String(format: "%.2f", speed),
            "altitude_m": String(format: "%.1f", altitude),
            "accuracy_m": String(format: "%.1f", accuracy),
            "state": state.rawValue
        ]
        debug("Location update", category: "Location", metadata: metadata)
    }

    func logRunDeleted(runId: UUID, reason: String) {
        let metadata: [String: String] = [
            "runId": runId.uuidString,
            "reason": reason
        ]
        info("Run deleted", category: "Runs", metadata: metadata)
    }

    func logFeedback(userId: String, userEmail: String, feedback: String, timestamp: String) {
        // Log to regular logs
        let metadata: [String: String] = [
            "userId": userId,
            "userEmail": userEmail,
            "timestamp": timestamp
        ]
        info("User feedback submitted", category: "Feedback", metadata: metadata)

        // Also store in dedicated feedback collection for email forwarding
        // This collection can be monitored by Firebase Cloud Functions to send emails
        let feedbackData: [String: Any] = [
            "userId": userId,
            "userEmail": userEmail,
            "feedback": feedback,
            "timestamp": Timestamp(date: Date()),
            "timestampISO": timestamp,
            "deviceInfo": deviceInfo,
            "appVersion": appVersion,
            "subject": "[SkiTracker User Comment]",
            "targetEmail": "pulseai@pulseaisolution.com",
            "status": "pending"  // Can be updated by Cloud Function after sending
        ]

        Task {
            do {
                try await db.collection("user_feedback").addDocument(data: feedbackData)
                print("[LoggingService] Feedback saved to Firebase")
            } catch {
                print("[LoggingService] Failed to save feedback: \(error)")
            }
        }
    }

    // MARK: - Core Logging

    private func log(level: LogLevel, category: String, message: String, metadata: [String: String]?) {
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            metadata: metadata,
            deviceInfo: deviceInfo,
            appVersion: appVersion,
            userId: AuthService.shared.currentUser?.uid
        )

        // Print to console
        print("[\(level.rawValue)] [\(category)] \(message)")
        if let meta = metadata {
            print("  Metadata: \(meta)")
        }

        // Store locally
        localLogs.append(entry)

        // Trim if too many
        if localLogs.count > maxLocalLogs {
            localLogs.removeFirst(localLogs.count - maxLocalLogs)
        }

        // Upload errors immediately
        if level == .error {
            uploadLogs()
        }
    }

    // MARK: - Upload to Firebase

    private func startUploadTimer() {
        uploadTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.uploadLogs()
        }
    }

    func uploadLogs() {
        guard !localLogs.isEmpty else { return }

        let logsToUpload = localLogs
        localLogs.removeAll()

        Task {
            do {
                let batch = db.batch()
                let logsCollection = db.collection("logs")

                for entry in logsToUpload {
                    let docRef = logsCollection.document()
                    var data: [String: Any] = [
                        "timestamp": Timestamp(date: entry.timestamp),
                        "level": entry.level.rawValue,
                        "category": entry.category,
                        "message": entry.message,
                        "deviceInfo": entry.deviceInfo,
                        "appVersion": entry.appVersion
                    ]

                    if let userId = entry.userId {
                        data["userId"] = userId
                    }

                    if let metadata = entry.metadata {
                        data["metadata"] = metadata
                    }

                    batch.setData(data, forDocument: docRef)
                }

                try await batch.commit()
                print("[LoggingService] Uploaded \(logsToUpload.count) logs to Firebase")
            } catch {
                print("[LoggingService] Failed to upload logs: \(error)")
                // Re-add logs that failed to upload
                localLogs.insert(contentsOf: logsToUpload, at: 0)
            }
        }
    }

    // MARK: - Force Upload (call before app termination)

    func flush() {
        uploadLogs()
    }
}

// MARK: - Convenience Global Function

func appLog(_ message: String, level: LogLevel = .info, category: String = "General", metadata: [String: String]? = nil) {
    switch level {
    case .debug:
        LoggingService.shared.debug(message, category: category, metadata: metadata)
    case .info:
        LoggingService.shared.info(message, category: category, metadata: metadata)
    case .warning:
        LoggingService.shared.warning(message, category: category, metadata: metadata)
    case .error:
        LoggingService.shared.error(message, category: category, metadata: metadata)
    }
}
