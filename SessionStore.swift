import Foundation

// MARK: - SessionStore

/// Handles reading and writing TrackSession data as JSON files
/// in the app's Documents directory.
final class SessionStore: ObservableObject {

    // MARK: - Published

    /// The last saved session, loaded on init
    @Published var lastSession: TrackSession?

    // MARK: - Constants

    private static let fileName = "last_session.json"

    // MARK: - Init

    init() {
        lastSession = Self.load()
    }

    // MARK: - File Path

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(fileName)
    }

    // MARK: - Save

    /// Save a session to Documents/last_session.json
    func save(_ session: TrackSession) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(session)
            try data.write(to: Self.fileURL, options: .atomic)
            DispatchQueue.main.async {
                self.lastSession = session
            }
            print("[SessionStore] Saved session with \(session.points.count) points to \(Self.fileURL.path)")
        } catch {
            print("[SessionStore] Save failed: \(error)")
        }
    }

    // MARK: - Load

    /// Load the last session from disk
    static func load() -> TrackSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[SessionStore] No saved session found.")
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let session = try decoder.decode(TrackSession.self, from: data)
            print("[SessionStore] Loaded session with \(session.points.count) points.")
            return session
        } catch {
            print("[SessionStore] Load failed: \(error)")
            return nil
        }
    }

    /// Reload from disk (e.g., pull-to-refresh)
    func reload() {
        lastSession = Self.load()
    }

    /// Delete the saved session
    func deleteSaved() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        lastSession = nil
    }
}
