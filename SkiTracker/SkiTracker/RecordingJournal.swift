import Foundation
import CoreLocation

private struct RecordingJournalManifest: Codable {
    let sessionID: UUID
    let startedAt: Date
    let deviceInfo: String?
    var resortName: String?
}

final class RecordingJournal {
    static let shared = RecordingJournal()

    private let queue = DispatchQueue(label: "com.pulseaisolution.skitracker.recording-journal")
    private let fileManager = FileManager.default
    private var pointHandle: FileHandle?
    private var pointCountSinceSync = 0

    private init() {}

    func begin(sessionID: UUID, startedAt: Date, deviceInfo: String?) {
        queue.sync {
            closeHandle()
            do {
                try ensureDirectory()
                let manifest = RecordingJournalManifest(
                    sessionID: sessionID,
                    startedAt: startedAt,
                    deviceInfo: deviceInfo,
                    resortName: nil
                )
                try writeManifest(manifest)
                try Data().write(to: pointsURL, options: .atomic)
                pointHandle = try FileHandle(forWritingTo: pointsURL)
                try pointHandle?.seekToEnd()
                pointCountSinceSync = 0
            } catch {
                print("[RecordingJournal] Unable to start journal: \(error)")
            }
        }
    }

    func append(_ location: CLLocation) {
        let point = TrackPoint(from: location)
        queue.async {
            do {
                if self.pointHandle == nil {
                    self.pointHandle = try FileHandle(forWritingTo: self.pointsURL)
                    try self.pointHandle?.seekToEnd()
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .millisecondsSince1970
                var data = try encoder.encode(point)
                data.append(0x0A)
                try self.pointHandle?.write(contentsOf: data)
                self.pointCountSinceSync += 1
                if self.pointCountSinceSync >= 10 {
                    try self.pointHandle?.synchronize()
                    self.pointCountSinceSync = 0
                }
            } catch {
                print("[RecordingJournal] Append failed: \(error)")
            }
        }
    }

    func updateResortName(_ resortName: String?) {
        queue.async {
            guard var manifest = self.readManifest() else { return }
            manifest.resortName = resortName
            try? self.writeManifest(manifest)
        }
    }

    func synchronize() {
        queue.sync {
            try? pointHandle?.synchronize()
            pointCountSinceSync = 0
        }
    }

    func discardActiveJournal() {
        queue.sync {
            closeHandle()
            try? fileManager.removeItem(at: manifestURL)
            try? fileManager.removeItem(at: pointsURL)
        }
    }

    func recoverInterruptedSession() -> TrackSession? {
        queue.sync {
            closeHandle()
            guard let manifest = readManifest(),
                  let data = try? Data(contentsOf: pointsURL),
                  !data.isEmpty else { return nil }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let points = data.split(separator: 0x0A).compactMap { line in
                try? decoder.decode(TrackPoint.self, from: Data(line))
            }
            guard points.count >= 2 else { return nil }

            var session = TrackSession(
                id: manifest.sessionID,
                startedAt: manifest.startedAt,
                deviceInfo: manifest.deviceInfo
            )
            session.endedAt = points.last?.timestamp
            session.resortName = manifest.resortName
            session.points = points
            return session
        }
    }

    private var directoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("RecordingJournal", isDirectory: true)
    }

    private var manifestURL: URL { directoryURL.appendingPathComponent("active.json") }
    private var pointsURL: URL { directoryURL.appendingPathComponent("active.points") }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = directoryURL
        try? mutableURL.setResourceValues(values)
    }

    private func writeManifest(_ manifest: RecordingJournalManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func readManifest() -> RecordingJournalManifest? {
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(RecordingJournalManifest.self, from: data)
    }

    private func closeHandle() {
        try? pointHandle?.synchronize()
        try? pointHandle?.close()
        pointHandle = nil
    }
}
