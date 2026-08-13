import Foundation

private struct PendingSessionUpload: Codable {
    let uid: String
    let sessionID: UUID
    let queuedAt: Date
}

final class PendingSessionUploadStore {
    static let shared = PendingSessionUploadStore()

    private let lock = NSLock()
    private let fileManager = FileManager.default

    private init() {}

    func enqueue(session: TrackSession, uid: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try ensureDirectory()
        let job = PendingSessionUpload(uid: uid, sessionID: session.id, queuedAt: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(job)
        try data.write(
            to: jobURL(uid: uid, sessionID: session.id),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func sessionIDs(for uid: String) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let job = try? decoder.decode(PendingSessionUpload.self, from: data),
                  job.uid == uid else { return nil }
            return job.sessionID
        }
    }

    func markComplete(uid: String, sessionID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: jobURL(uid: uid, sessionID: sessionID))
    }

    private var directoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PendingUploads", isDirectory: true)
    }

    private func jobURL(uid: String, sessionID: UUID) -> URL {
        let safeUID = uid.replacingOccurrences(of: "/", with: "_")
        return directoryURL.appendingPathComponent("\(safeUID)_\(sessionID.uuidString).json")
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directoryURL
        try? mutableURL.setResourceValues(values)
    }
}
