import Foundation
import CoreLocation
import CryptoKit

nonisolated struct TrackStorageArtifacts: Sendable {
    let canonicalData: Data
    let previewData: Data
    let canonicalChecksum: String
    let previewChecksum: String
}

nonisolated struct StoredSegmentDescriptor: Codable, Sendable {
    let id: UUID
    let type: SkiingState
    let startTime: Date
    let endTime: Date?
    let startIndex: Int
    let endIndex: Int

    enum CodingKeys: String, CodingKey {
        case id = "i"
        case type = "y"
        case startTime = "s"
        case endTime = "e"
        case startIndex = "a"
        case endIndex = "b"
    }
}

nonisolated private struct StoredTrackPoint: Codable, Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let speed: Double
    let course: Double
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case latitude = "a"
        case longitude = "o"
        case altitude = "h"
        case horizontalAccuracy = "x"
        case verticalAccuracy = "v"
        case speed = "s"
        case course = "c"
        case timestamp = "t"
    }

    init(_ point: TrackPoint) {
        latitude = point.latitude
        longitude = point.longitude
        altitude = point.altitude
        horizontalAccuracy = point.horizontalAccuracy
        verticalAccuracy = point.verticalAccuracy
        speed = point.speed
        course = point.course
        timestamp = point.timestamp
    }

    var trackPoint: TrackPoint {
        TrackPoint(
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            speed: speed,
            course: course,
            timestamp: timestamp
        )
    }
}

nonisolated private struct StoredTrackArchive: Codable, Sendable {
    let schemaVersion: Int
    let sessionID: UUID
    let startedAt: Date
    let endedAt: Date?
    let resortName: String?
    let deviceInfo: String?
    let points: [StoredTrackPoint]
    let segments: [StoredSegmentDescriptor]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "v"
        case sessionID = "i"
        case startedAt = "s"
        case endedAt = "e"
        case resortName = "r"
        case deviceInfo = "d"
        case points = "p"
        case segments = "g"
    }
}

nonisolated enum TrackArchiveCodec {
    static let schemaVersion = 4
    static let metricAlgorithmVersion = 1

    static func artifacts(for session: TrackSession) throws -> TrackStorageArtifacts {
        let canonical = try encode(session: session, selectedIndexes: Array(session.points.indices))
        let previewIndexes = replayPreviewIndexes(for: session)
        let preview = try encode(session: session, selectedIndexes: previewIndexes)
        return TrackStorageArtifacts(
            canonicalData: canonical,
            previewData: preview,
            canonicalChecksum: checksum(canonical),
            previewChecksum: checksum(preview)
        )
    }

    static func decode(_ data: Data) throws -> TrackSession {
        let decompressed = try (data as NSData).decompressed(using: .lzfse) as Data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(StoredTrackArchive.self, from: decompressed)
        guard archive.schemaVersion <= schemaVersion else {
            throw NSError(
                domain: "TrackArchiveCodec",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Track archive uses a newer unsupported schema."]
            )
        }

        let points = archive.points.map(\.trackPoint)
        var session = TrackSession(id: archive.sessionID, startedAt: archive.startedAt, deviceInfo: archive.deviceInfo)
        session.endedAt = archive.endedAt
        session.resortName = archive.resortName
        session.points = points
        session.segments = archive.segments.compactMap { descriptor in
            guard !points.isEmpty else { return nil }
            let start = min(max(0, descriptor.startIndex), points.count - 1)
            let end = min(max(start, descriptor.endIndex), points.count - 1)
            return RunSegment(
                id: descriptor.id,
                type: descriptor.type,
                startTime: descriptor.startTime,
                endTime: descriptor.endTime,
                points: Array(points[start...end])
            )
        }
        session.remoteTrackVersion = schemaVersion
        session.remotePointCount = points.count
        session.remoteSegmentCount = session.segments.count
        return session
    }

    static func segmentDescriptors(for session: TrackSession) -> [StoredSegmentDescriptor] {
        descriptors(segments: session.segments, in: session.points)
    }

    private static func encode(session: TrackSession, selectedIndexes: [Int]) throws -> Data {
        let validIndexes = selectedIndexes
            .filter { session.points.indices.contains($0) }
            .sorted()
        let selectedPoints = validIndexes.map { session.points[$0] }
        let originalDescriptors = descriptors(segments: session.segments, in: session.points)
        let remappedDescriptors = originalDescriptors.compactMap { descriptor -> StoredSegmentDescriptor? in
            guard !validIndexes.isEmpty else { return nil }
            let start = nearestSelectedPosition(to: descriptor.startIndex, selectedIndexes: validIndexes)
            let end = nearestSelectedPosition(to: descriptor.endIndex, selectedIndexes: validIndexes)
            guard start <= end else { return nil }
            return StoredSegmentDescriptor(
                id: descriptor.id,
                type: descriptor.type,
                startTime: descriptor.startTime,
                endTime: descriptor.endTime,
                startIndex: start,
                endIndex: end
            )
        }

        let archive = StoredTrackArchive(
            schemaVersion: schemaVersion,
            sessionID: session.id,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            resortName: session.resortName,
            deviceInfo: session.deviceInfo,
            points: selectedPoints.map(StoredTrackPoint.init),
            segments: remappedDescriptors
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let encoded = try encoder.encode(archive)
        return try (encoded as NSData).compressed(using: .lzfse) as Data
    }

    private static func descriptors(segments: [RunSegment], in points: [TrackPoint]) -> [StoredSegmentDescriptor] {
        guard !points.isEmpty else { return [] }
        return segments.compactMap { segment in
            guard let first = segment.points.first, let last = segment.points.last else { return nil }
            let start = nearestPointIndex(to: first.timestamp, in: points)
            let end = nearestPointIndex(to: last.timestamp, in: points)
            return StoredSegmentDescriptor(
                id: segment.id,
                type: segment.type,
                startTime: segment.startTime,
                endTime: segment.endTime,
                startIndex: min(start, end),
                endIndex: max(start, end)
            )
        }
    }

    private static func replayPreviewIndexes(for session: TrackSession) -> [Int] {
        let points = session.points
        guard points.count > 2 else { return Array(points.indices) }

        var kept: Set<Int> = [0, points.count - 1]
        for descriptor in descriptors(segments: session.segments, in: points) {
            kept.insert(descriptor.startIndex)
            kept.insert(descriptor.endIndex)
        }

        if let fastest = points.indices.max(by: { points[$0].speed < points[$1].speed }) {
            for index in max(0, fastest - 2)...min(points.count - 1, fastest + 2) {
                kept.insert(index)
            }
        }
        if let highest = points.indices.max(by: { points[$0].altitude < points[$1].altitude }) {
            kept.insert(highest)
        }
        if let lowest = points.indices.min(by: { points[$0].altitude < points[$1].altitude }) {
            kept.insert(lowest)
        }

        var lastKept = 0
        for index in 1..<(points.count - 1) {
            let elapsed = points[index].timestamp.timeIntervalSince(points[lastKept].timestamp)
            let from = CLLocation(latitude: points[lastKept].latitude, longitude: points[lastKept].longitude)
            let to = CLLocation(latitude: points[index].latitude, longitude: points[index].longitude)
            let distance = to.distance(from: from)
            let courseDelta = angularDifference(points[index].course, points[lastKept].course)
            if elapsed >= 3 || distance >= 18 || courseDelta >= 12 {
                kept.insert(index)
                lastKept = index
            }
        }
        return kept.sorted()
    }

    private static func nearestPointIndex(to timestamp: Date, in points: [TrackPoint]) -> Int {
        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        if low == 0 { return 0 }
        if low == points.count { return points.count - 1 }
        let before = points[low - 1].timestamp.timeIntervalSince(timestamp).magnitude
        let after = points[low].timestamp.timeIntervalSince(timestamp).magnitude
        return before <= after ? low - 1 : low
    }

    private static func nearestSelectedPosition(to originalIndex: Int, selectedIndexes: [Int]) -> Int {
        var bestPosition = 0
        var bestDistance = Int.max
        for (position, value) in selectedIndexes.enumerated() {
            let distance = abs(value - originalIndex)
            if distance < bestDistance {
                bestDistance = distance
                bestPosition = position
            }
        }
        return bestPosition
    }

    private static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
        guard lhs >= 0, rhs >= 0 else { return 0 }
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
