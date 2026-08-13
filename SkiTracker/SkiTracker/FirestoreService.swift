import Foundation
import Combine
import CryptoKit
import FirebaseFirestore
import UIKit

final class FirestoreService: ObservableObject {
    static let shared = FirestoreService()

    private let db = Firestore.firestore()
    private let userDefaults = UserDefaults.standard
    private let trackStorageVersion = TrackArchiveCodec.schemaVersion
    private let syncHashStorePrefix = "firestore_session_hashes_"

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var errorMessage: String?

    private init() {}

    private func userDocument(uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    private func sessionsCollection(uid: String) -> CollectionReference {
        userDocument(uid: uid).collection("sessions")
    }

    private func pointChunkCollection(sessionRef: DocumentReference, activeTrackVersion: Int?) -> CollectionReference {
        guard let activeTrackVersion, activeTrackVersion > 0 else {
            return sessionRef.collection("pointChunks")
        }
        return sessionRef.collection("pointChunks_v\(activeTrackVersion)")
    }

    private func segmentChunkCollection(sessionRef: DocumentReference, activeTrackVersion: Int?) -> CollectionReference {
        guard let activeTrackVersion, activeTrackVersion > 0 else {
            return sessionRef.collection("segmentChunks")
        }
        return sessionRef.collection("segmentChunks_v\(activeTrackVersion)")
    }

    // MARK: User profile

    func saveUserProfile(_ user: AppUser) async {
        do {
            try await userDocument(uid: user.uid).setData([
                "uid": user.uid,
                "email": user.email ?? "",
                "displayName": user.displayName ?? "",
                "photoURL": user.photoURL ?? "",
                "provider": user.provider,
                "updatedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            await publish(error: error)
        }
    }

    func uploadHeadshot(_ image: UIImage, uid: String) async throws {
        guard let encoded = encodeHeadshot(image) else {
            throw NSError(domain: "FirestoreService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode headshot image."])
        }
        try await userDocument(uid: uid).setData([
            "headshotBase64": encoded,
            "headshotUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }

    func loadHeadshot(uid: String) async -> UIImage? {
        do {
            let snapshot = try await userDocument(uid: uid).getDocument()
            guard let base64 = snapshot.data()?["headshotBase64"] as? String,
                  let data = Data(base64Encoded: base64) else { return nil }
            return UIImage(data: data)
        } catch {
            await publish(error: error)
            return nil
        }
    }

    // MARK: Session sync

    func uploadSession(_ session: TrackSession, uid: String) async throws {
        try PendingSessionUploadStore.shared.enqueue(session: session, uid: uid)
        let signature = sessionSignature(session)
        try await uploadSessionV4(session, uid: uid, signature: signature)
        PendingSessionUploadStore.shared.markComplete(uid: uid, sessionID: session.id)
        var signatures = loadSessionSignatures(uid: uid)
        signatures[session.id.uuidString] = signature
        saveSessionSignatures(signatures, uid: uid)
    }

    func uploadAllSessions(_ sessions: [TrackSession], uid: String) async {
        await setSyncing(true)
        do {
            var signatures = loadSessionSignatures(uid: uid)

            // Jobs survive process termination and are always attempted first.
            let queuedIDs = Set(PendingSessionUploadStore.shared.sessionIDs(for: uid))
            for session in sessions where queuedIDs.contains(session.id) && !session.points.isEmpty {
                let signature = sessionSignature(session)
                try await uploadSessionV4(session, uid: uid, signature: signature)
                PendingSessionUploadStore.shared.markComplete(uid: uid, sessionID: session.id)
                signatures[session.id.uuidString] = signature
            }

            for session in sessions where !session.points.isEmpty && !queuedIDs.contains(session.id) {
                let signature = sessionSignature(session)
                if signatures[session.id.uuidString] == signature { continue }
                try PendingSessionUploadStore.shared.enqueue(session: session, uid: uid)
                try await uploadSessionV4(session, uid: uid, signature: signature)
                PendingSessionUploadStore.shared.markComplete(uid: uid, sessionID: session.id)
                signatures[session.id.uuidString] = signature
            }

            let retainedIDs = Set(sessions.map { $0.id.uuidString })
            signatures = signatures.filter { retainedIDs.contains($0.key) }
            saveSessionSignatures(signatures, uid: uid)
            await MainActor.run {
                self.lastSyncDate = Date()
                self.isSyncing = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isSyncing = false
            }
        }
    }

    private func uploadSessionV4(_ session: TrackSession, uid: String, signature: String) async throws {
        guard !session.points.isEmpty else { return }
        let uploaded = try await TrackStorageService.shared.upload(session: session, uid: uid)
        let sessionRef = sessionsCollection(uid: uid).document(session.id.uuidString)
        let existingData = try? await sessionRef.getDocument().data()
        let descriptors = TrackArchiveCodec.segmentDescriptors(for: session)
        let descriptorByID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let segmentSummaries: [[String: Any]] = session.segments.compactMap { segment in
            guard let descriptor = descriptorByID[segment.id] else { return nil }
            var value: [String: Any] = [
                "id": segment.id.uuidString,
                "type": segment.type.rawValue,
                "startTime": Timestamp(date: segment.startTime),
                "startIndex": descriptor.startIndex,
                "endIndex": descriptor.endIndex,
                "distanceMeters": segment.totalDistanceMeters,
                "maxSpeedKmh": segment.maxSpeedKmh,
                "avgSpeedKmh": segment.avgSpeedKmh,
                "elevationDrop": segment.elevationDrop
            ]
            if let endTime = segment.endTime { value["endTime"] = Timestamp(date: endTime) }
            return value
        }

        var data: [String: Any] = [
            "id": session.id.uuidString,
            "startedAt": Timestamp(date: session.startedAt),
            "resortName": session.resortName ?? "",
            "deviceInfo": session.deviceInfo ?? "",
            "schemaVersion": trackStorageVersion,
            "trackStorageVersion": trackStorageVersion,
            "metricAlgorithmVersion": TrackArchiveCodec.metricAlgorithmVersion,
            "syncStatus": "ready",
            "totalDistanceKm": session.totalDistanceKm,
            "maxSpeedKmh": session.maxSpeedKmh,
            "avgSpeedKmh": session.avgSpeedKmh,
            "maxAltitude": session.maxAltitude,
            "minAltitude": session.minAltitude,
            "elevationDrop": session.elevationDrop,
            "totalVerticalDrop": session.totalVerticalDrop,
            "durationSeconds": session.durationSeconds,
            "runCount": session.runCount,
            "liftCount": session.liftCount,
            "pointCount": session.points.count,
            "segmentCount": session.segments.count,
            "segmentSummaries": segmentSummaries,
            "canonicalTrackPath": uploaded.canonicalPath,
            "previewTrackPath": uploaded.previewPath,
            "canonicalTrackBytes": uploaded.canonicalBytes,
            "previewTrackBytes": uploaded.previewBytes,
            "canonicalChecksum": uploaded.canonicalChecksum,
            "previewChecksum": uploaded.previewChecksum,
            "sessionSignature": signature,
            "activeTrackVersion": trackStorageVersion,
            "updatedAt": FieldValue.serverTimestamp(),
            "uploadedAt": FieldValue.serverTimestamp(),
            "points": FieldValue.delete(),
            "segments": FieldValue.delete()
        ]
        if let endedAt = session.endedAt { data["endedAt"] = Timestamp(date: endedAt) }

        // Storage is uploaded first; the ready document is the atomic publication point.
        try await sessionRef.setData(data, merge: true)

        if let oldCanonical = existingData?["canonicalTrackPath"] as? String, oldCanonical != uploaded.canonicalPath {
            try? await TrackStorageService.shared.delete(path: oldCanonical)
        }
        if let oldPreview = existingData?["previewTrackPath"] as? String, oldPreview != uploaded.previewPath {
            try? await TrackStorageService.shared.delete(path: oldPreview)
        }
        let legacyVersion = existingData?["activeTrackVersion"] as? Int
        if (existingData?["trackStorageVersion"] as? Int ?? 1) < trackStorageVersion {
            try? await deleteTrackSubcollections(sessionRef, activeTrackVersion: legacyVersion)
        }
    }

    func downloadSessions(uid: String, summaryOnly: Bool = true) async -> [TrackSession] {
        await setSyncing(true)
        do {
            var sessions: [TrackSession] = []
            var lastDocument: QueryDocumentSnapshot?
            repeat {
                var query: Query = sessionsCollection(uid: uid)
                    .order(by: "startedAt", descending: true)
                    .limit(to: 200)
                if let lastDocument { query = query.start(afterDocument: lastDocument) }
                let snapshot = try await query.getDocuments()
                for document in snapshot.documents {
                    if let session = await parseSession(
                        from: document.data(),
                        docRef: document.reference,
                        includeTrackData: !summaryOnly
                    ) {
                        sessions.append(session)
                    }
                }
                lastDocument = snapshot.documents.last
                if snapshot.documents.count < 200 { break }
            } while lastDocument != nil
            await MainActor.run {
                self.lastSyncDate = Date()
                self.isSyncing = false
            }
            return sessions
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isSyncing = false
            }
            return []
        }
    }

    func hydrateSessionTrack(_ session: TrackSession, uid: String) async -> TrackSession? {
        let document = sessionsCollection(uid: uid).document(session.id.uuidString)
        do {
            let snapshot = try await document.getDocument()
            guard let data = snapshot.data() else { return nil }
            return await parseSession(from: data, docRef: document, includeTrackData: true)
        } catch {
            await publish(error: error)
            return nil
        }
    }

    func deleteSession(_ session: TrackSession, uid: String) async {
        do {
            let reference = sessionsCollection(uid: uid).document(session.id.uuidString)
            let data = try await reference.getDocument().data()
            if let path = data?["canonicalTrackPath"] as? String { try? await TrackStorageService.shared.delete(path: path) }
            if let path = data?["previewTrackPath"] as? String { try? await TrackStorageService.shared.delete(path: path) }
            try await deleteTrackSubcollections(reference, activeTrackVersion: data?["activeTrackVersion"] as? Int)
            try await reference.delete()
            PendingSessionUploadStore.shared.markComplete(uid: uid, sessionID: session.id)
            var signatures = loadSessionSignatures(uid: uid)
            signatures.removeValue(forKey: session.id.uuidString)
            saveSessionSignatures(signatures, uid: uid)
        } catch {
            await publish(error: error)
        }
    }

    func deleteAllSessions(uid: String) async {
        let sessions = await downloadSessions(uid: uid)
        for session in sessions { await deleteSession(session, uid: uid) }
        saveSessionSignatures([:], uid: uid)
    }

    // MARK: Parsing and legacy compatibility

    private func parseSession(from data: [String: Any], docRef: DocumentReference, includeTrackData: Bool) async -> TrackSession? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let startedAt = (data["startedAt"] as? Timestamp)?.dateValue() else { return nil }

        var session = TrackSession(id: id, startedAt: startedAt, deviceInfo: data["deviceInfo"] as? String)
        session.endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        let resort = (data["resortName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        session.resortName = resort?.isEmpty == false ? resort : nil
        let storageVersion = int(data["trackStorageVersion"]) ?? 1
        session.remoteTrackVersion = storageVersion
        session.remotePointCount = int(data["pointCount"])
        session.remoteSegmentCount = int(data["segmentCount"])
        session.remoteSummary = TrackSessionMetricSummary(
            totalDistanceKm: double(data["totalDistanceKm"]),
            maxSpeedKmh: double(data["maxSpeedKmh"]),
            avgSpeedKmh: double(data["avgSpeedKmh"]),
            maxAltitude: double(data["maxAltitude"]),
            minAltitude: double(data["minAltitude"]),
            elevationDrop: double(data["elevationDrop"]),
            totalVerticalDrop: double(data["totalVerticalDrop"], fallback: double(data["elevationDrop"])),
            runCount: int(data["runCount"]) ?? 0,
            liftCount: int(data["liftCount"]) ?? 0,
            pointCount: int(data["pointCount"]) ?? 0,
            segmentCount: int(data["segmentCount"]) ?? 0
        )
        if !includeTrackData {
            // v1-v3 documents did not persist run/lift counts in the summary document.
            if storageVersion < trackStorageVersion, data["runCount"] == nil {
                do {
                    let version = int(data["activeTrackVersion"])
                    session.segments = try await loadSegmentChunks(
                        from: docRef,
                        expectedCount: session.remoteSegmentCount,
                        activeTrackVersion: version
                    )
                } catch {
                    print("[FirestoreService] Legacy summary segments failed for \(idString): \(error)")
                }
            }
            return session
        }

        if storageVersion >= trackStorageVersion {
            let objects: [(String?, String?)] = [
                (data["canonicalTrackPath"] as? String, data["canonicalChecksum"] as? String),
                (data["previewTrackPath"] as? String, data["previewChecksum"] as? String)
            ]
            for (pathValue, expectedChecksum) in objects {
                guard let path = pathValue else { continue }
                do {
                    let objectData = try await TrackStorageService.shared.download(path: path)
                    if let expectedChecksum,
                       TrackArchiveCodec.checksum(objectData) != expectedChecksum {
                        throw NSError(
                            domain: "FirestoreService",
                            code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "Track checksum mismatch."]
                        )
                    }
                    var restored = try TrackArchiveCodec.decode(objectData)
                    restored.remoteSummary = session.remoteSummary
                    return restored
                } catch {
                    print("[FirestoreService] Track object \(path) failed: \(error)")
                }
            }
            return session
        }

        if storageVersion >= 2 {
            do {
                let version = int(data["activeTrackVersion"])
                session.points = try await loadPointChunks(from: docRef, expectedCount: session.remotePointCount, activeTrackVersion: version)
                session.segments = try await loadSegmentChunks(from: docRef, expectedCount: session.remoteSegmentCount, activeTrackVersion: version)
            } catch {
                print("[FirestoreService] Legacy chunks failed for \(idString): \(error)")
            }
        }
        if session.points.isEmpty, let points = data["points"] as? [[String: Any]] { session.points = decodePoints(points) }
        if session.segments.isEmpty, let segments = data["segments"] as? [[String: Any]] { session.segments = decodeSegments(segments) }
        return session
    }

    private func decodePoints(_ values: [[String: Any]]) -> [TrackPoint] {
        values.compactMap { value in
            guard let latitude = value["lat"] as? Double,
                  let longitude = value["lng"] as? Double,
                  let altitude = value["alt"] as? Double,
                  let timestamp = (value["ts"] as? Timestamp)?.dateValue() else { return nil }
            return TrackPoint(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                horizontalAccuracy: double(value["hAcc"], fallback: 20),
                verticalAccuracy: double(value["vAcc"], fallback: 20),
                speed: double(value["speed"], fallback: -1),
                course: double(value["course"], fallback: -1),
                timestamp: timestamp
            )
        }
    }

    private func decodeSegments(_ values: [[String: Any]]) -> [RunSegment] {
        values.compactMap { value in
            guard let rawType = value["type"] as? String,
                  let type = SkiingState(rawValue: rawType),
                  let start = (value["startTime"] as? Timestamp)?.dateValue() else { return nil }
            return RunSegment(
                id: UUID(uuidString: value["id"] as? String ?? "") ?? UUID(),
                type: type,
                startTime: start,
                endTime: (value["endTime"] as? Timestamp)?.dateValue(),
                points: decodePoints(value["points"] as? [[String: Any]] ?? [])
            )
        }
    }

    private func loadPointChunks(from sessionRef: DocumentReference, expectedCount: Int?, activeTrackVersion: Int?) async throws -> [TrackPoint] {
        let snapshot = try await pointChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion)
            .order(by: "index").getDocuments()
        var points = snapshot.documents.flatMap { decodePoints($0.data()["points"] as? [[String: Any]] ?? []) }
        if let expectedCount, points.count > expectedCount { points.removeSubrange(expectedCount...) }
        return points
    }

    private func loadSegmentChunks(from sessionRef: DocumentReference, expectedCount: Int?, activeTrackVersion: Int?) async throws -> [RunSegment] {
        let snapshot = try await segmentChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion)
            .order(by: "index").getDocuments()
        var segments = snapshot.documents.flatMap { decodeSegments($0.data()["segments"] as? [[String: Any]] ?? []) }
        if let expectedCount, segments.count > expectedCount { segments.removeSubrange(expectedCount...) }
        return segments
    }

    private func deleteTrackSubcollections(_ sessionRef: DocumentReference, activeTrackVersion: Int?) async throws {
        var collections = [sessionRef.collection("pointChunks"), sessionRef.collection("segmentChunks")]
        if let activeTrackVersion, activeTrackVersion < trackStorageVersion {
            collections.append(pointChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion))
            collections.append(segmentChunkCollection(sessionRef: sessionRef, activeTrackVersion: activeTrackVersion))
        }
        for collection in collections { try await deleteCollectionDocuments(collection) }
    }

    private func deleteCollectionDocuments(_ collection: CollectionReference) async throws {
        while true {
            let snapshot = try await collection.limit(to: 200).getDocuments()
            guard !snapshot.documents.isEmpty else { return }
            let batch = db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            if snapshot.documents.count < 200 { return }
        }
    }

    // MARK: Helpers

    private func loadSessionSignatures(uid: String) -> [String: String] {
        userDefaults.dictionary(forKey: syncHashStorePrefix + uid) as? [String: String] ?? [:]
    }

    private func saveSessionSignatures(_ signatures: [String: String], uid: String) {
        userDefaults.set(signatures, forKey: syncHashStorePrefix + uid)
    }

    private func sessionSignature(_ session: TrackSession) -> String {
        let first = session.points.first
        let last = session.points.last
        let seed = [
            session.id.uuidString,
            session.startedAt.timeIntervalSince1970.description,
            session.endedAt?.timeIntervalSince1970.description ?? "",
            session.resortName ?? "",
            String(format: "%.5f", session.totalDistanceKm),
            String(format: "%.5f", session.maxSpeedKmh),
            "p:\(session.points.count)",
            "s:\(session.segments.count)",
            String(format: "%.6f", first?.latitude ?? 0),
            String(format: "%.6f", last?.latitude ?? 0),
            last?.timestamp.timeIntervalSince1970.description ?? ""
        ].joined(separator: "|")
        return SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func int(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private func double(_ value: Any?, fallback: Double = 0) -> Double { (value as? NSNumber)?.doubleValue ?? fallback }

    private func encodeHeadshot(_ image: UIImage) -> String? {
        resizedHeadshot(image).jpegData(compressionQuality: 0.72)?.base64EncodedString()
    }

    private func resizedHeadshot(_ image: UIImage, maxSide: CGFloat = 512) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }

    private func setSyncing(_ value: Bool) async {
        await MainActor.run {
            self.isSyncing = value
            if value { self.errorMessage = nil }
        }
    }

    private func publish(error: Error) async {
        await MainActor.run { self.errorMessage = error.localizedDescription }
    }
}
