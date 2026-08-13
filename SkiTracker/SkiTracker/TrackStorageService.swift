import Foundation
import FirebaseStorage

struct UploadedTrackArtifacts {
    let canonicalPath: String
    let previewPath: String
    let canonicalBytes: Int
    let previewBytes: Int
    let canonicalChecksum: String
    let previewChecksum: String
}

final class TrackStorageService {
    static let shared = TrackStorageService()

    private let storage = Storage.storage()
    private let maximumDownloadBytes: Int64 = 64 * 1024 * 1024

    private init() {}

    func upload(session: TrackSession, uid: String) async throws -> UploadedTrackArtifacts {
        let artifacts = try await Task.detached(priority: .utility) {
            try TrackArchiveCodec.artifacts(for: session)
        }.value
        let basePath = "tracks/\(uid)/\(session.id.uuidString)"
        let canonicalPath = "\(basePath)/canonical-v\(TrackArchiveCodec.schemaVersion)-\(artifacts.canonicalChecksum.prefix(16)).lzfse"
        let previewPath = "\(basePath)/preview-v\(TrackArchiveCodec.schemaVersion)-\(artifacts.previewChecksum.prefix(16)).lzfse"

        try await put(artifacts.canonicalData, path: canonicalPath, checksum: artifacts.canonicalChecksum)
        do {
            try await put(artifacts.previewData, path: previewPath, checksum: artifacts.previewChecksum)
        } catch {
            try? await delete(path: canonicalPath)
            throw error
        }

        return UploadedTrackArtifacts(
            canonicalPath: canonicalPath,
            previewPath: previewPath,
            canonicalBytes: artifacts.canonicalData.count,
            previewBytes: artifacts.previewData.count,
            canonicalChecksum: artifacts.canonicalChecksum,
            previewChecksum: artifacts.previewChecksum
        )
    }

    func download(path: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            storage.reference(withPath: path).getData(maxSize: maximumDownloadBytes) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "TrackStorageService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Track download returned no data."]
                    ))
                }
            }
        }
    }

    func delete(path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.reference(withPath: path).delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func put(_ data: Data, path: String, checksum: String) async throws {
        let metadata = StorageMetadata()
        metadata.contentType = "application/octet-stream"
        metadata.customMetadata = [
            "schemaVersion": String(TrackArchiveCodec.schemaVersion),
            "sha256": checksum
        ]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            storage.reference(withPath: path).putData(data, metadata: metadata) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
