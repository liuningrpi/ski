import Foundation
import CoreLocation

enum SkiMetrics {

    // Ignore short fragments; 200 ft ~= 60.96 m.
    static let minRecordedRunDistanceMeters = 60.96
    private static let maxPlausibleSpeedMps = 35.0   // ~78 mph
    private static let minMovingSpeedMps = 2.0       // exclude slow coasting / queue drift
    private static let maxAscentRateForMoving = 0.15 // m/s; filter clear lift ascent from avg speed
    private static let peakSensorAccuracyMeters = 25.0
    private static let minDerivedPeakIntervalSeconds = 1.0
    private static let minDerivedPeakDistanceMeters = 4.0

    static func totalDistanceMeters(points: [TrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for idx in 1..<points.count {
            guard let step = validStepDistanceMeters(from: points[idx - 1], to: points[idx]) else { continue }
            total += step
        }
        return total
    }

    static func averageSpeedKmh(points: [TrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var movingDistance = 0.0
        var movingDuration = 0.0

        for idx in 1..<points.count {
            let prev = points[idx - 1]
            let curr = points[idx]
            guard let dt = validDeltaTime(from: prev, to: curr),
                  let step = validStepDistanceMeters(from: prev, to: curr) else { continue }

            let stepSpeed = step / dt
            let ascentRate = (curr.altitude - prev.altitude) / dt
            if stepSpeed >= minMovingSpeedMps, ascentRate <= maxAscentRateForMoving {
                movingDistance += step
                movingDuration += dt
            }
        }

        guard movingDuration > 0 else { return 0 }
        return (movingDistance / movingDuration) * 3.6
    }

    static func peakSpeedKmh(points: [TrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        var candidates: [Double] = []
        candidates.reserveCapacity(points.count)

        for idx in 1..<points.count {
            let prev = points[idx - 1]
            let curr = points[idx]

            var pointCandidate: Double?

            // Prefer sensor speed when accuracy is good; it is usually less spiky than point-to-point derivation.
            if curr.speed >= 0,
               curr.speed.isFinite,
               curr.speed <= maxPlausibleSpeedMps,
               curr.horizontalAccuracy > 0,
               curr.horizontalAccuracy <= peakSensorAccuracyMeters {
                pointCandidate = curr.speed
            }

            guard let dt = validDeltaTime(from: prev, to: curr),
                  let step = validStepDistanceMeters(from: prev, to: curr) else { continue }

            let derived = step / dt
            if derived.isFinite,
               derived >= 0,
               derived <= maxPlausibleSpeedMps,
               dt >= minDerivedPeakIntervalSeconds,
               step >= minDerivedPeakDistanceMeters,
               prev.horizontalAccuracy > 0,
               prev.horizontalAccuracy <= peakSensorAccuracyMeters,
               curr.horizontalAccuracy > 0,
               curr.horizontalAccuracy <= peakSensorAccuracyMeters {
                pointCandidate = pointCandidate.map { min($0, derived * 1.08) } ?? derived
            }

            if let pointCandidate {
                candidates.append(pointCandidate)
            }
        }

        guard !candidates.isEmpty else { return 0 }
        let confirmedPeak = stablePeakSpeedMps(candidates)
        return confirmedPeak * 3.6
    }

    private static func stablePeakSpeedMps(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        guard samples.count >= 3 else { return samples.max() ?? 0 }

        var stablePeaks: [Double] = []
        stablePeaks.reserveCapacity(samples.count - 2)

        for idx in 1..<(samples.count - 1) {
            let window = [samples[idx - 1], samples[idx], samples[idx + 1]].sorted()
            stablePeaks.append(window[1]) // rolling median suppresses one-point spikes
        }

        return stablePeaks.max() ?? samples.max() ?? 0
    }

    private static func validDeltaTime(from prev: TrackPoint, to curr: TrackPoint) -> Double? {
        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        guard dt > 0, dt <= 6 else { return nil }
        return dt
    }

    private static func validStepDistanceMeters(from prev: TrackPoint, to curr: TrackPoint) -> Double? {
        guard let dt = validDeltaTime(from: prev, to: curr) else { return nil }
        let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
        let step = currLoc.distance(from: prevLoc)
        guard step.isFinite, step >= 0 else { return nil }

        // Dynamic teleport filter: allow longer steps when sampling interval is longer.
        let dynamicMax = max(80.0, dt * maxPlausibleSpeedMps)
        guard step <= dynamicMax else { return nil }
        return step
    }
}
