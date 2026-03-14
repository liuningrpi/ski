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
        segments.filter { $0.type == .skiing }.count
    }

    /// Number of lift rides
    var liftCount: Int {
        segments.filter { $0.type == .lift }.count
    }

    /// Total vertical drop from skiing segments only
    var totalVerticalDrop: Double {
        segments.filter { $0.type == .skiing }.reduce(0) { $0 + $1.cumulativeDescent }
    }

    /// Skiing runs only
    var skiingRuns: [RunSegment] {
        segments.filter { $0.type == .skiing }
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
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let step = curr.distance(from: prev)
            // Filter teleportation: skip single step > 100m
            if step <= 100 {
                total += step
            }
        }
        return total
    }

    /// Total distance in kilometers
    var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    /// Maximum speed in km/h (only valid speed values, filter > 60 m/s ≈ 216 km/h)
    var maxSpeedKmh: Double {
        let sensorMax = points
            .map { $0.speed }
            .filter { $0 >= 0 && $0.isFinite && $0 <= 60 }
            .max() ?? 0

        var derivedMax: Double = 0
        if points.count >= 2 {
            for i in 1..<points.count {
                let prev = points[i - 1]
                let curr = points[i]
                let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
                guard dt > 0, dt <= 5 else { continue }
                let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
                let stepSpeed = currLoc.distance(from: prevLoc) / dt
                if stepSpeed.isFinite && stepSpeed >= 0 && stepSpeed <= 35 {
                    derivedMax = max(derivedMax, stepSpeed)
                }
            }
        }

        return max(sensorMax, derivedMax) * 3.6
    }

    /// Average speed in km/h
    var avgSpeedKmh: Double {
        guard durationSeconds > 0 else { return 0 }
        return (totalDistanceMeters / durationSeconds) * 3.6
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
