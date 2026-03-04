import Foundation
import Combine

// MARK: - SessionStore

/// Handles reading and writing TrackSession data as JSON files
/// in the app's Documents directory. Supports multiple sessions.
final class SessionStore: ObservableObject {

    // MARK: - Published

    /// All saved sessions, sorted by date (newest first)
    @Published var sessions: [TrackSession] = []

    // MARK: - Constants

    private static let fileName = "ski_sessions.json"

    // MARK: - Init

    init() {
        sessions = Self.loadAll()
    }

    // MARK: - File Path

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    // MARK: - Save

    /// Save a new session
    func save(_ session: TrackSession) {
        var allSessions = sessions
        allSessions.insert(session, at: 0) // Add to beginning (newest first)
        saveAll(allSessions)
    }

    /// Save all sessions to disk
    private func saveAll(_ allSessions: [TrackSession]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(allSessions)
            try data.write(to: Self.fileURL, options: .atomic)
            DispatchQueue.main.async {
                self.sessions = allSessions
            }
            print("[SessionStore] Saved \(allSessions.count) sessions to \(Self.fileURL.path)")
        } catch {
            print("[SessionStore] Save failed: \(error)")
        }
    }

    // MARK: - Load

    /// Load all sessions from disk
    static func loadAll() -> [TrackSession] {
        // First try to load from new format
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let sessions = try decoder.decode([TrackSession].self, from: data)
                print("[SessionStore] Loaded \(sessions.count) sessions.")
                return sessions
            } catch {
                print("[SessionStore] Load failed: \(error)")
            }
        }

        // Try to migrate from old single-session format
        let oldFileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("last_session.json")
        if FileManager.default.fileExists(atPath: oldFileURL.path) {
            do {
                let data = try Data(contentsOf: oldFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let session = try decoder.decode(TrackSession.self, from: data)
                print("[SessionStore] Migrated 1 session from old format.")
                // Delete old file after migration
                try? FileManager.default.removeItem(at: oldFileURL)
                return [session]
            } catch {
                print("[SessionStore] Migration failed: \(error)")
            }
        }

        print("[SessionStore] No saved sessions found.")
        return []
    }

    /// Reload from disk
    func reload() {
        sessions = Self.loadAll()
    }

    // MARK: - Delete

    /// Delete a specific session
    func delete(_ session: TrackSession) {
        var allSessions = sessions
        allSessions.removeAll { $0.id == session.id }
        saveAll(allSessions)
    }

    /// Delete all sessions
    func deleteAll() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        DispatchQueue.main.async {
            self.sessions = []
        }
    }

    // MARK: - Convenience

    /// The most recent session (for backward compatibility)
    var lastSession: TrackSession? {
        sessions.first
    }
}
