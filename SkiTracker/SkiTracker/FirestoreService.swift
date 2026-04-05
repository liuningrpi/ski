import Foundation
import Combine
import CryptoKit
import FirebaseFirestore

// MARK: - Firestore Service

final class FirestoreService: ObservableObject {

    static let shared = FirestoreService()

    private let db = Firestore.firestore()
    private let userDefaults = UserDefaults.standard

    private let pointChunkSize = 250
    private let segmentChunkSize = 20
    private let trackStorageVersion = 3
    private let syncHashStorePrefix = "firestore_session_hashes_"

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

    private func pointChunkCollection(sessionRef: DocumentReference, activeTrackVersion: Int?) -> CollectionReference {
        if let activeTrackVersion, activeTrackVersion > 0 {
            return sessionRef.collection("pointChunks_v\(activeTrackVersion)")
        }
        return sessionRef.collection("pointChunks")
    }

    private func segmentChunkCollection(sessionRef: DocumentReference, activeTrackVersion: Int?) -> CollectionReference {
        if let activeTrackVersion, activeTrackVersion > 0 {
            return sessionRef.collection("segmentChunks_v\(activeTrackVersion)")
        }
        return sessionRef.collection("segmentChunks")
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
        let signature = sessionSignature(session)
        try await uploadSession(session, uid: uid, signature: signature)

        var signatures = loadSessionSignatures(uid: uid)
        signatures[session.id.uuidString] = signature
        saveSessionSignatures(signatures, uid: uid)
    }

    /// Upload all sessions for a user
    func uploadAllSessions(_ sessions: [TrackSession], uid: String) async {
        await MainActor.run {
            isSyncing = true
            errorMessage = nil
        }

        do {
            var signatures = loadSessionSignatures(uid: uid)
            let existingIDs = Set(sessions.map { $0.id.uuidString })

            for session in sessions {
                let signature = sessionSignature(session)
                let sessionID = session.id.uuidString
                if signatures[sessionID] == signature {
                    continue
                }

                try await uploadSession(session, uid: uid, signature: signature)
                signatures[sessionID] = signature
            }

            signatures = signatures.filter { existingIDs.contains($0.key) }
            saveSessionSignatures(signatures, uid: uid)

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

    private func uploadSession(_ session: TrackSession, uid: String, signature: String) async throws {
        let docRef = sessionsCollection(uid: uid).document(session.id.uuidString)
        let existingData = try? await docRef.getDocument().data()
        let previousTrackVersion = existingData?["activeTrackVersion"] as? Int
        let nextTrackVersion = max((previousTrackVersion ?? 0) + 1, 1)

        var data: [String: Any] = [
            "id": session.id.uuidString,
            "startedAt": Timestamp(date: session.startedAt),
            "resortName": session.resortName ?? "",
            "deviceInfo": session.deviceInfo ?? "",
            "totalDistanceKm": session.totalDistanceKm,
            "maxSpeedKmh": session.maxSpeedKmh,
            "avgSpeedKmh": session.avgSpeedKmh,
            "maxAltitude": session.maxAltitude,
            "elevationDrop": session.elevationDrop,
            "durationSeconds": session.durationSeconds,
            "pointCount": session.points.count,
            "segmentCount": session.segments.count,
            "trackStorageVersion": trackStorageVersion,
            "pointChunkSize": pointChunkSize,
            "pointChunkCount": chunkCount(total: session.points.count, size: pointChunkSize),
            "segmentChunkSize": segmentChunkSize,
            "segmentChunkCount": chunkCount(total: session.segments.count, size: segmentChunkSize),
            "sessionSignature": signature,
            "activeTrackVersion": nextTrackVersion,
            "uploadedAt": FieldValue.serverTimestamp(),
            "points": FieldValue.delete(),
            "segments": FieldValue.delete()
        ]

        if let endedAt = session.endedAt {
            data["endedAt"] = Timestamp(date: endedAt)
        }

        let nextPointChunks = pointChunkCollection(sessionRef: docRef, activeTrackVersion: nextTrackVersion)
        let nextSegmentChunks = segmentChunkCollection(sessionRef: docRef, activeTrackVersion: nextTrackVersion)
        try await writePointChunks(session.points, to: nextPointChunks)
        try await writeSegmentChunks(session.segments, to: nextSegmentChunks)
        try await docRef.setData(data, merge: true)

        if let previousTrackVersion, previousTrackVersion != nextTrackVersion {
            try? await deleteCollectionDocuments(pointChunkCollection(sessionRef: docRef, activeTrackVersion: previousTrackVersion))
            try? await deleteCollectionDocuments(segmentChunkCollection(sessionRef: docRef, activeTrackVersion: previousTrackVersion))
        }
    }

    /// Download all sessions for a user
    func downloadSessions(uid: String, summaryOnly: Bool = true) async -> [TrackSession] {
        await MainActor.run {
            isSyncing = true
            errorMessage = nil
        }

        do {
            let snapshot = try await sessionsCollection(uid: uid)
                .order(by: "startedAt", descending: true)
                .getDocuments()

            var sessions: [TrackSession] = []
            sessions.reserveCapacity(snapshot.documents.count)

            for doc in snapshot.documents {
                if let session = await parseSession(from: doc.data(), docRef: doc.reference, includeTrackData: !summaryOnly) {
                    sessions.append(session)
                }
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

    func hydrateSessionTrack(_ session: TrackSession, uid: String) async -> TrackSession? {
        let docRef = sessionsCollection(uid: uid).document(session.id.uuidString)
        do {
            let snapshot = try await docRef.getDocument()
            guard let data = snapshot.data() else { return nil }
            return await parseSession(from: data, docRef: docRef, includeTrackData: true)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    /// Delete a session from Firestore
    func deleteSession(_ session: TrackSession, uid: String) async {
        do {
            let sessionRef = sessionsCollection(uid: uid).document(session.id.uuidString)
            let snapshot = try await sessionRef.getDocument()
            try await deleteTrackSubcollections(sessionRef, activeTrackVersion: snapshot.data()?["activeTrackVersion"] as? Int)
            try await sessionRef.delete()

            var signatures = loadSessionSignatures(uid: uid)
            signatures.removeValue(forKey: session.id.uuidString)
            saveSessionSignatures(signatures, uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete all sessions for a user
    func deleteAllSessions(uid: String) async {
        do {
            let snapshot = try await sessionsCollection(uid: uid).getDocuments()
            for doc in snapshot.documents {
                try await deleteTrackSubcollections(doc.reference, activeTrackVersion: doc.data()["activeTrackVersion"] as? Int)
                try await doc.reference.delete()
            }
            saveSessionSignatures([:], uid: uid)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parse Session

    private func parseSession(from data: [String: Any], docRef: DocumentReference, includeTrackData: Bool) async -> TrackSession? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let startedAtTimestamp = data["startedAt"] as? Timestamp else {
            return nil
        }

        let startedAt = startedAtTimestamp.dateValue()
        let endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        let resortName = (data["resortName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceInfo = data["deviceInfo"] as? String

        var session = TrackSession(id: id, startedAt: startedAt, deviceInfo: deviceInfo)
        session.endedAt = endedAt
        session.resortName = resortName?.isEmpty == false ? resortName : nil
        session.remoteTrackVersion = data["activeTrackVersion"] as? Int
        session.remotePointCount = data["pointCount"] as? Int
        session.remoteSegmentCount = data["segmentCount"] as? Int

        let storageVersion = data["trackStorageVersion"] as? Int ?? 1

        guard includeTrackData else {
            return session
        }

        if storageVersion >= 2 {
            let expectedPointCount = session.remotePointCount
            let expectedSegmentCount = session.remoteSegmentCount

            do {
                session.points = try await loadPointChunks(
                    from: docRef,
                    expectedCount: expectedPointCount,
                    activeTrackVersion: session.remoteTrackVersion
                )
                session.segments = try await loadSegmentChunks(
                    from: docRef,
                    expectedCount: expectedSegmentCount,
                    activeTrackVersion: session.remoteTrackVersion
                )
            } catch {
                print("[FirestoreService] Failed to parse chunked track for session \(idString): \(error)")
            }

            // Backward-compatible fallback while users migrate from inline data.
            if session.points.isEmpty, let pointsData = data["points"] as? [[String: Any]] {
                session.points = decodePoints(pointsData)
            }
            if session.segments.isEmpty, let segmentsData = data["segments"] as? [[String: Any]] {
                session.segments = decodeSegments(segmentsData)
            }
        } else {
            if let pointsData = data["points"] as? [[String: Any]] {
                session.points = decodePoints(pointsData)
            }
            if let segmentsData = data["segments"] as? [[String: Any]] {
                session.segments = decodeSegments(segmentsData)
            }
        }

        return session
    }

    private func decodePoints(_ pointsData: [[String: Any]]) -> [TrackPoint] {
        pointsData.compactMap { pointData -> TrackPoint? in
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

    private func decodeSegments(_ segmentsData: [[String: Any]]) -> [RunSegment] {
        segmentsData.compactMap { segmentData -> RunSegment? in
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
                segment.points = decodePoints(segmentPointsData)
            }
            return segment
        }
    }

    private func loadPointChunks(from sessionRef: DocumentReference, expectedCount: Int?, activeTrackVersion: Int?) async throws -> [TrackPoint] {
        let snapshot = try await pointChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion)
            .order(by: "index", descending: false)
            .getDocuments()

        var points: [TrackPoint] = []
        if let expectedCount {
            points.reserveCapacity(expectedCount)
        }

        for doc in snapshot.documents {
            guard let pointsData = doc.data()["points"] as? [[String: Any]] else { continue }
            points.append(contentsOf: decodePoints(pointsData))
            if let expectedCount, points.count >= expectedCount {
                break
            }
        }

        if let expectedCount, points.count > expectedCount {
            points.removeSubrange(expectedCount..<points.count)
        }

        return points
    }

    private func loadSegmentChunks(from sessionRef: DocumentReference, expectedCount: Int?, activeTrackVersion: Int?) async throws -> [RunSegment] {
        let snapshot = try await segmentChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion)
            .order(by: "index", descending: false)
            .getDocuments()

        var segments: [RunSegment] = []
        if let expectedCount {
            segments.reserveCapacity(expectedCount)
        }

        for doc in snapshot.documents {
            guard let segmentsData = doc.data()["segments"] as? [[String: Any]] else { continue }
            segments.append(contentsOf: decodeSegments(segmentsData))
            if let expectedCount, segments.count >= expectedCount {
                break
            }
        }

        if let expectedCount, segments.count > expectedCount {
            segments.removeSubrange(expectedCount..<segments.count)
        }

        return segments
    }

    // MARK: - Chunked Upload Helpers

    private func writePointChunks(_ points: [TrackPoint], to collection: CollectionReference) async throws {
        let encodedPoints = points.map { point in
            [
                "lat": point.latitude,
                "lng": point.longitude,
                "alt": point.altitude,
                "speed": point.speed,
                "ts": Timestamp(date: point.timestamp)
            ]
        }

        let chunks = chunked(encodedPoints, size: pointChunkSize)
        guard !chunks.isEmpty else { return }

        var batch = db.batch()
        var writesInBatch = 0

        for (index, chunk) in chunks.enumerated() {
            let docID = String(format: "%05d", index)
            let docRef = collection.document(docID)
            batch.setData([
                "index": index,
                "points": chunk
            ], forDocument: docRef)
            writesInBatch += 1

            if writesInBatch >= 400 {
                try await batch.commit()
                batch = db.batch()
                writesInBatch = 0
            }
        }

        if writesInBatch > 0 {
            try await batch.commit()
        }
    }

    private func writeSegmentChunks(_ segments: [RunSegment], to collection: CollectionReference) async throws {
        let encodedSegments = segments.map { segment -> [String: Any] in
            let segmentPoints = segment.points.map { point in
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

        let chunks = chunked(encodedSegments, size: segmentChunkSize)
        guard !chunks.isEmpty else { return }

        var batch = db.batch()
        var writesInBatch = 0

        for (index, chunk) in chunks.enumerated() {
            let docID = String(format: "%05d", index)
            let docRef = collection.document(docID)
            batch.setData([
                "index": index,
                "segments": chunk
            ], forDocument: docRef)
            writesInBatch += 1

            if writesInBatch >= 400 {
                try await batch.commit()
                batch = db.batch()
                writesInBatch = 0
            }
        }

        if writesInBatch > 0 {
            try await batch.commit()
        }
    }

    private func deleteTrackSubcollections(_ sessionRef: DocumentReference, activeTrackVersion: Int?) async throws {
        try await deleteCollectionDocuments(sessionRef.collection("pointChunks"))
        try await deleteCollectionDocuments(sessionRef.collection("segmentChunks"))
        if let activeTrackVersion {
            try await deleteCollectionDocuments(pointChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion))
            try await deleteCollectionDocuments(segmentChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion))
        }
    }

    private func deleteCollectionDocuments(_ collection: CollectionReference, pageSize: Int = 200) async throws {
        while true {
            let snapshot = try await collection.limit(to: pageSize).getDocuments()
            if snapshot.documents.isEmpty {
                return
            }

            let batch = db.batch()
            for doc in snapshot.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()

            if snapshot.documents.count < pageSize {
                return
            }
        }
    }

    // MARK: - Sync Signature Cache

    private func loadSessionSignatures(uid: String) -> [String: String] {
        let key = syncHashStorePrefix + uid
        return userDefaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    private func saveSessionSignatures(_ signatures: [String: String], uid: String) {
        let key = syncHashStorePrefix + uid
        userDefaults.set(signatures, forKey: key)
    }

    private func sessionSignature(_ session: TrackSession) -> String {
        let firstPoint = session.points.first
        let lastPoint = session.points.last

        let signatureSeed = [
            session.id.uuidString,
            session.startedAt.timeIntervalSince1970.description,
            (session.endedAt?.timeIntervalSince1970.description ?? ""),
            (session.resortName ?? ""),
            String(format: "%.5f", session.totalDistanceKm),
            String(format: "%.5f", session.maxSpeedKmh),
            String(format: "%.5f", session.avgSpeedKmh),
            String(format: "%.5f", session.maxAltitude),
            String(format: "%.5f", session.elevationDrop),
            String(format: "%.5f", session.durationSeconds),
            "p:\(session.points.count)",
            "s:\(session.segments.count)",
            String(format: "%.6f", firstPoint?.latitude ?? 0),
            String(format: "%.6f", firstPoint?.longitude ?? 0),
            String(format: "%.2f", firstPoint?.altitude ?? 0),
            String(format: "%.6f", lastPoint?.latitude ?? 0),
            String(format: "%.6f", lastPoint?.longitude ?? 0),
            String(format: "%.2f", lastPoint?.altitude ?? 0),
            String(format: "%.2f", lastPoint?.speed ?? 0),
            (lastPoint?.timestamp.timeIntervalSince1970.description ?? "")
        ].joined(separator: "|")

        let digest = SHA256.hash(data: Data(signatureSeed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func chunkCount(total: Int, size: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(ceil(Double(total) / Double(size)))
    }

    private func chunked<T>(_ values: [T], size: Int) -> [[T]] {
        guard size > 0, !values.isEmpty else { return [] }
        var chunks: [[T]] = []
        chunks.reserveCapacity(chunkCount(total: values.count, size: size))

        var index = 0
        while index < values.count {
            let end = min(index + size, values.count)
            chunks.append(Array(values[index..<end]))
            index = end
        }
        return chunks
    }
}
