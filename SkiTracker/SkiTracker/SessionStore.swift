import Foundation
import Combine
import CoreLocation

/// Persists each session independently so one save never rewrites the user's full history.
@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [TrackSession] = []

    private static let legacyFileName = "ski_sessions.json"
    private let fileManager = FileManager.default

    init() {
        sessions = Self.loadAll()
        recoverInterruptedRecording()
    }

    @discardableResult
    func save(_ session: TrackSession) -> Bool {
        do {
            try Self.write(session)
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
            sessions.sort { $0.startedAt > $1.startedAt }
            return true
        } catch {
            print("[SessionStore] Save failed for \(session.id): \(error)")
            return false
        }
    }

    static func loadAll() -> [TrackSession] {
        migrateLegacyFilesIfNeeded()
        do {
            try ensureDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            let decoder = makeDecoder()
            let loaded = urls
                .filter { $0.pathExtension == "json" }
                .compactMap { url -> TrackSession? in
                    do {
                        return try decoder.decode(TrackSession.self, from: Data(contentsOf: url))
                    } catch {
                        print("[SessionStore] Ignoring unreadable session \(url.lastPathComponent): \(error)")
                        return nil
                    }
                }
                .sorted { $0.startedAt > $1.startedAt }
            print("[SessionStore] Loaded \(loaded.count) sessions.")
            return loaded
        } catch {
            print("[SessionStore] Load failed: \(error)")
            return []
        }
    }

    func reload() {
        sessions = Self.loadAll()
    }

    func delete(_ session: TrackSession) {
        try? fileManager.removeItem(at: Self.sessionURL(session.id))
        sessions.removeAll { $0.id == session.id }
    }

    func deleteAll() {
        for session in sessions {
            try? fileManager.removeItem(at: Self.sessionURL(session.id))
        }
        sessions = []
    }

    func update(_ session: TrackSession) {
        _ = save(session)
    }

    func deleteRun(runId: UUID, fromSession sessionId: UUID) {
        guard var session = sessions.first(where: { $0.id == sessionId }) else { return }
        session.deleteRun(id: runId)
        update(session)
    }

    /// Adds cloud-only summaries while preserving richer local tracks for matching IDs.
    func mergeRemote(_ remoteSessions: [TrackSession]) {
        var merged = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        for remote in remoteSessions {
            if let local = merged[remote.id], !local.points.isEmpty {
                continue
            }
            merged[remote.id] = remote
            _ = try? Self.write(remote)
        }
        sessions = merged.values.sorted { $0.startedAt > $1.startedAt }
    }

    var lastSession: TrackSession? { sessions.first }

    private func recoverInterruptedRecording() {
        guard var recovered = RecordingJournal.shared.recoverInterruptedSession() else { return }
        let segmenter = RunSegmenter()
        for point in recovered.points {
            let location = CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude,
                horizontalAccuracy: point.horizontalAccuracy,
                verticalAccuracy: point.verticalAccuracy,
                course: point.course,
                speed: point.speed,
                timestamp: point.timestamp
            )
            segmenter.processLocation(location)
        }
        segmenter.finalizeCurrentSegment(forceIncludeCurrentSkiing: true)
        recovered.segments = segmenter.segments
        if sessions.contains(where: { $0.id == recovered.id }) || save(recovered) {
            RecordingJournal.shared.discardActiveJournal()
            print("[SessionStore] Recovered interrupted session \(recovered.id).")
        }
    }

    private static var sessionsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Sessions", isDirectory: true)
    }

    private static func sessionURL(_ id: UUID) -> URL {
        sessionsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = sessionsDirectory
        try? mutableURL.setResourceValues(values)
    }

    private static func write(_ session: TrackSession) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(
            to: sessionURL(session.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func migrateLegacyFilesIfNeeded() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let decoder = makeDecoder()
        var recovered: [TrackSession] = []
        let multiURL = documents.appendingPathComponent(legacyFileName)
        if let data = try? Data(contentsOf: multiURL),
           let sessions = try? decoder.decode([TrackSession].self, from: data) {
            recovered.append(contentsOf: sessions)
        }
        let singleURL = documents.appendingPathComponent("last_session.json")
        if let data = try? Data(contentsOf: singleURL),
           let session = try? decoder.decode(TrackSession.self, from: data),
           !recovered.contains(where: { $0.id == session.id }) {
            recovered.append(session)
        }

        guard !recovered.isEmpty else { return }
        do {
            try ensureDirectory()
            let existingIDs = Set((try FileManager.default.contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )).compactMap { url -> UUID? in
                guard let data = try? Data(contentsOf: url),
                      let session = try? decoder.decode(TrackSession.self, from: data) else { return nil }
                return session.id
            })
            for session in recovered where !existingIDs.contains(session.id) { try write(session) }
            try? FileManager.default.removeItem(at: multiURL)
            try? FileManager.default.removeItem(at: singleURL)
            print("[SessionStore] Migrated \(recovered.count) legacy sessions.")
        } catch {
            print("[SessionStore] Legacy migration failed; source files retained: \(error)")
        }
    }
}
