import Foundation
import CoreLocation

// MARK: - TrackPoint

/// A single GPS point recorded during a skiing session.
/// All fields are Codable for JSON serialization.
struct TrackPoint: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double          // meters
    let horizontalAccuracy: Double // meters
    let verticalAccuracy: Double   // meters
    let speed: Double              // m/s  (negative means invalid)
    let course: Double             // degrees (0–360, negative means invalid)
    let timestamp: Date

    init(from location: CLLocation) {
        self.id = UUID()
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.speed = location.speed
        self.course = location.course
        self.timestamp = location.timestamp
    }

    /// Manual initializer for Firestore deserialization
    init(latitude: Double, longitude: Double, altitude: Double,
         horizontalAccuracy: Double, verticalAccuracy: Double,
         speed: Double, course: Double, timestamp: Date) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    /// Convenience: convert back to CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - TrackSession

/// Represents one complete skiing recording session.
struct TrackSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var points: [TrackPoint]
    let deviceInfo: String?
    var segments: [RunSegment]

    init(startedAt: Date, deviceInfo: String? = nil) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = nil
        self.points = []
        self.deviceInfo = deviceInfo
        self.segments = []
    }

    /// Manual initializer for Firestore deserialization
    init(id: UUID, startedAt: Date, deviceInfo: String?) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.points = []
        self.deviceInfo = deviceInfo
        self.segments = []
    }

    // MARK: - Segment Statistics

    /// Number of skiing runs
    var runCount: Int {
        segments.filter {
            $0.type == .skiing &&
            $0.totalDistanceMeters >= SkiMetrics.minRecordedRunDistanceMeters
        }.count
    }

    /// Number of lift rides
    var liftCount: Int {
        segments.filter { $0.type == .lift }.count
    }

    /// Total vertical drop from skiing segments only
    var totalVerticalDrop: Double {
        segments
            .filter {
                $0.type == .skiing &&
                $0.totalDistanceMeters >= SkiMetrics.minRecordedRunDistanceMeters
            }
            .reduce(0) { $0 + $1.cumulativeDescent }
    }

    /// Skiing runs only
    var skiingRuns: [RunSegment] {
        segments.filter {
            $0.type == .skiing &&
            $0.totalDistanceMeters >= SkiMetrics.minRecordedRunDistanceMeters
        }
    }

    /// Lift rides only
    var liftRides: [RunSegment] {
        segments.filter { $0.type == .lift }
    }

    /// Delete a specific run by ID
    mutating func deleteRun(id: UUID) {
        segments.removeAll { $0.id == id }
        LoggingService.shared.logRunDeleted(runId: id, reason: "User deleted from history")
    }

    // MARK: - Computed Statistics

    /// Total duration in seconds
    var durationSeconds: TimeInterval {
        guard let end = endedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return end.timeIntervalSince(startedAt)
    }

    /// Formatted duration string (HH:mm:ss)
    var durationFormatted: String {
        let total = Int(durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// Total distance in meters, with teleport filtering (skip single-step > 100m)
    var totalDistanceMeters: Double {
        SkiMetrics.totalDistanceMeters(points: points)
    }

    /// Total distance in kilometers
    var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    /// Maximum speed in km/h (only valid speed values, filter > 60 m/s ≈ 216 km/h)
    var maxSpeedKmh: Double {
        SkiMetrics.peakSpeedKmh(points: points)
    }

    /// Average speed in km/h
    var avgSpeedKmh: Double {
        SkiMetrics.averageSpeedKmh(points: points)
    }

    /// Maximum altitude in meters
    var maxAltitude: Double {
        points.map { $0.altitude }.max() ?? 0
    }

    /// Minimum altitude in meters
    var minAltitude: Double {
        points.map { $0.altitude }.min() ?? 0
    }

    /// Elevation drop (max - min)
    var elevationDrop: Double {
        maxAltitude - minAltitude
    }
}
