import Foundation
import Testing
@testable import SkiTracker

struct SkiTrackerTests {
    @Test func trackArchiveRoundTripPreservesRawGPSAndSegments() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [TrackPoint] = []
        for index in 0..<20 {
            let point = TrackPoint(
                latitude: 40.0 + Double(index) * 0.0001,
                longitude: -105.0 - Double(index) * 0.0001,
                altitude: 3_000 - Double(index) * 2,
                horizontalAccuracy: 3.5 + Double(index) / 10,
                verticalAccuracy: 5.5,
                speed: 4 + Double(index),
                course: Double(index) * 5,
                timestamp: start.addingTimeInterval(Double(index))
            )
            points.append(point)
        }
        let segmentID = UUID()
        let segment = RunSegment(
            id: segmentID,
            type: .skiing,
            startTime: points[2].timestamp,
            endTime: points[17].timestamp,
            points: Array(points[2...17])
        )
        var session = TrackSession(id: UUID(), startedAt: start, deviceInfo: "Test iPhone")
        session.endedAt = points.last?.timestamp
        session.resortName = "Test Mountain"
        session.points = points
        session.segments = [segment]

        let artifacts = try TrackArchiveCodec.artifacts(for: session)
        let restored = try TrackArchiveCodec.decode(artifacts.canonicalData)

        #expect(restored.id == session.id)
        #expect(restored.points.count == points.count)
        #expect(restored.segments.count == 1)
        #expect(restored.segments[0].id == segmentID)
        #expect(restored.segments[0].points.count == segment.points.count)
        #expect(restored.points[7].horizontalAccuracy == points[7].horizontalAccuracy)
        #expect(restored.points[7].verticalAccuracy == points[7].verticalAccuracy)
        #expect(restored.points[7].course == points[7].course)
    }

    @Test func previewArchiveRetainsEndpointsAndReducesDenseTrack() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var points: [TrackPoint] = []
        for index in 0..<1_000 {
            let point = TrackPoint(
                latitude: 40 + Double(index) * 0.000001,
                longitude: -105,
                altitude: 3_000 - Double(index) * 0.1,
                horizontalAccuracy: 4,
                verticalAccuracy: 6,
                speed: 10,
                course: 180,
                timestamp: start.addingTimeInterval(Double(index) * 0.2)
            )
            points.append(point)
        }
        var session = TrackSession(id: UUID(), startedAt: start, deviceInfo: nil)
        session.endedAt = points.last?.timestamp
        session.points = points

        let artifacts = try TrackArchiveCodec.artifacts(for: session)
        let preview = try TrackArchiveCodec.decode(artifacts.previewData)

        #expect(preview.points.count < points.count)
        #expect(preview.points.first?.timestamp == points.first?.timestamp)
        #expect(preview.points.last?.timestamp == points.last?.timestamp)
    }
}
