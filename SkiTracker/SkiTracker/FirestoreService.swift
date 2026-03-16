import Foundation
import Combine
import FirebaseFirestore

// MARK: - Firestore Service

final class FirestoreService: ObservableObject {

    static let shared = FirestoreService()

    private let db = Firestore.firestore()

    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Collections

    private func userDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func sessionsCollection(uid: String) -> CollectionReference {
        userDocument(uid: uid).collection("sessions")
    }

    // MARK: - User Profile

    func saveUserProfile(_ user: AppUser) async {
        do {
            let data: [String: Any] = [
                "uid": user.uid,
                "email": user.email ?? "",
                "displayName": user.displayName ?? "",
                "photoURL": user.photoURL ?? "",
                "provider": user.provider,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await userDocument(uid: user.uid).setData(data, merge: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sessions

    /// Upload a single session to Firestore
    func uploadSession(_ session: TrackSession, uid: String) async throws {
        let docRef = sessionsCollection(uid: uid).document(session.id.uuidString)

        var data: [String: Any] = [
            "id": session.id.uuidString,
            "startedAt": Timestamp(date: session.startedAt),
            "deviceInfo": session.deviceInfo ?? "",
            "totalDistanceKm": session.totalDistanceKm,
            "maxSpeedKmh": session.maxSpeedKmh,
            "avgSpeedKmh": session.avgSpeedKmh,
            "maxAltitude": session.maxAltitude,
            "elevationDrop": session.elevationDrop,
            "durationSeconds": session.durationSeconds,
            "pointCount": session.points.count,
            "uploadedAt": FieldValue.serverTimestamp()
        ]

        if let endedAt = session.endedAt {
            data["endedAt"] = Timestamp(date: endedAt)
        }

        // Store points as a sub-array (simplified for performance)
        // For very large tracks, consider storing points in a subcollection
        let pointsData = session.points.map { point -> [String: Any] in
            return [
                "lat": point.latitude,
                "lng": point.longitude,
                "alt": point.altitude,
                "speed": point.speed,
                "ts": Timestamp(date: point.timestamp)
            ]
        }
        data["points"] = pointsData

        // Persist segmented ski/lift tracks so history map can render lift lines after sync.
        let segmentsData = session.segments.map { segment -> [String: Any] in
            let segmentPoints = segment.points.map { point -> [String: Any] in
                [
                    "lat": point.latitude,
                    "lng": point.longitude,
                    "alt": point.altitude,
                    "speed": point.speed,
                    "ts": Timestamp(date: point.timestamp)
                ]
            }
            var encoded: [String: Any] = [
                "id": segment.id.uuidString,
                "type": segment.type.rawValue,
                "startTime": Timestamp(date: segment.startTime),
                "points": segmentPoints
            ]
            if let endTime = segment.endTime {
                encoded["endTime"] = Timestamp(date: endTime)
            }
            return encoded
        }
        data["segments"] = segmentsData

        try await docRef.setData(data)
    }

    /// Upload all sessions for a user
    func uploadAllSessions(_ sessions: [TrackSession], uid: String) async {
        await MainActor.run {
            isSyncing = true
            errorMessage = nil
        }

        do {
            for session in sessions {
                try await uploadSession(session, uid: uid)
            }
            await MainActor.run {
                lastSyncDate = Date()
                isSyncing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSyncing = false
            }
        }
    }

    /// Download all sessions for a user
    func downloadSessions(uid: String) async -> [TrackSession] {
        await MainActor.run {
            isSyncing = true
            errorMessage = nil
        }

        do {
            let snapshot = try await sessionsCollection(uid: uid)
                .order(by: "startedAt", descending: true)
                .getDocuments()

            let sessions = snapshot.documents.compactMap { doc -> TrackSession? in
                return parseSession(from: doc.data())
            }

            await MainActor.run {
                isSyncing = false
                lastSyncDate = Date()
            }
            return sessions
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSyncing = false
            }
            return []
        }
    }

    /// Delete a session from Firestore
    func deleteSession(_ session: TrackSession, uid: String) async {
        do {
            try await sessionsCollection(uid: uid).document(session.id.uuidString).delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete all sessions for a user
    func deleteAllSessions(uid: String) async {
        do {
            let snapshot = try await sessionsCollection(uid: uid).getDocuments()
            for doc in snapshot.documents {
                try await doc.reference.delete()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parse Session

    private func parseSession(from data: [String: Any]) -> TrackSession? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let startedAtTimestamp = data["startedAt"] as? Timestamp else {
            return nil
        }

        let startedAt = startedAtTimestamp.dateValue()
        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        let deviceInfo = data["deviceInfo"] as? String

        var session = TrackSession(id: id, startedAt: startedAt, deviceInfo: deviceInfo)
        session.endedAt = endedAt

        // Parse points
        if let pointsData = data["points"] as? [[String: Any]] {
            session.points = pointsData.compactMap { pointData -> TrackPoint? in
                guard let lat = pointData["lat"] as? Double,
                      let lng = pointData["lng"] as? Double,
                      let alt = pointData["alt"] as? Double,
                      let speed = pointData["speed"] as? Double,
                      let ts = pointData["ts"] as? Timestamp else {
                    return nil
                }
                return TrackPoint(
                    latitude: lat,
                    longitude: lng,
                    altitude: alt,
                    horizontalAccuracy: 0,
                    verticalAccuracy: 0,
                    speed: speed,
                    course: 0,
                    timestamp: ts.dateValue()
                )
            }
        }

        if let segmentsData = data["segments"] as? [[String: Any]] {
            session.segments = segmentsData.compactMap { segmentData -> RunSegment? in
                guard let typeRaw = segmentData["type"] as? String,
                      let type = SkiingState(rawValue: typeRaw),
                      let startTS = segmentData["startTime"] as? Timestamp else {
                    return nil
                }

                var segment = RunSegment(type: type, startTime: startTS.dateValue())
                if let endTS = segmentData["endTime"] as? Timestamp {
                    segment.endTime = endTS.dateValue()
                }

                if let segmentPointsData = segmentData["points"] as? [[String: Any]] {
                    segment.points = segmentPointsData.compactMap { pointData in
                        guard let lat = pointData["lat"] as? Double,
                              let lng = pointData["lng"] as? Double,
                              let alt = pointData["alt"] as? Double,
                              let speed = pointData["speed"] as? Double,
                              let ts = pointData["ts"] as? Timestamp else {
                            return nil
                        }
                        return TrackPoint(
                            latitude: lat,
                            longitude: lng,
                            altitude: alt,
                            horizontalAccuracy: 0,
                            verticalAccuracy: 0,
                            speed: speed,
                            course: 0,
                            timestamp: ts.dateValue()
                        )
                    }
                }

                return segment
            }
        }

        return session
    }
}
