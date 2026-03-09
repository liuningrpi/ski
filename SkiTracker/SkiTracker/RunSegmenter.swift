import Foundation
import CoreLocation
import Combine

// MARK: - Skiing State

enum SkiingState: String, Codable {
    case idle = "idle"           // Not started or paused
    case skiing = "skiing"       // Actively skiing downhill
    case lift = "lift"           // On ski lift going up
    case stopped = "stopped"     // Waiting in line, resting, or stationary
}

// MARK: - Run Segment

struct RunSegment: Codable, Identifiable {
    let id: UUID
    let type: SkiingState
    let startTime: Date
    var endTime: Date?
    var points: [TrackPoint]

    init(type: SkiingState, startTime: Date) {
        self.id = UUID()
        self.type = type
        self.startTime = startTime
        self.endTime = nil
        self.points = []
    }

    // MARK: - Computed Properties

    var durationSeconds: TimeInterval {
        guard let end = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return end.timeIntervalSince(startTime)
    }

    var durationFormatted: String {
        let total = Int(durationSeconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var totalDistanceMeters: Double {
        guard points.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].latitude, longitude: points[i-1].longitude)
            let curr = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
            let step = curr.distance(from: prev)
            if step <= 100 { // Filter teleportation
                total += step
            }
        }
        return total
    }

    var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    var maxSpeedKmh: Double {
        let validSpeeds = points.map { $0.speed }.filter { $0 >= 0 && $0.isFinite && $0 <= 60 }
        guard let maxMs = validSpeeds.max() else { return 0 }
        return maxMs * 3.6
    }

    var avgSpeedKmh: Double {
        guard durationSeconds > 0 else { return 0 }
        return (totalDistanceMeters / durationSeconds) * 3.6
    }

    var elevationDrop: Double {
        guard let maxAlt = points.map({ $0.altitude }).max(),
              let minAlt = points.map({ $0.altitude }).min() else { return 0 }
        return maxAlt - minAlt
    }

    var startAltitude: Double {
        points.first?.altitude ?? 0
    }

    var endAltitude: Double {
        points.last?.altitude ?? 0
    }

    var verticalChange: Double {
        endAltitude - startAltitude
    }
}

// MARK: - Location Sample (for windowed analysis)

struct LocationSample {
    let location: CLLocation
    let timestamp: Date
    let speed: Double           // m/s
    let altitude: Double        // meters
    let altitudeChangeRate: Double  // m/s (positive = ascending)
    let horizontalAccuracy: Double
}

// MARK: - Run Segmenter

final class RunSegmenter: ObservableObject {

    // MARK: - Configuration Thresholds

    struct Config {
        // Production profile for outdoor ski run/lift detection.

        // Speed thresholds (m/s)
        var skiingMinSpeed: Double = 2.0
        var liftMinSpeed: Double = 0.5
        var liftMaxSpeed: Double = 6.5
        var stoppedMaxSpeed: Double = 0.8

        // Altitude change rate thresholds (m/s)
        var skiingDescentRate: Double = -0.25   // Descending
        var liftAscentRate: Double = 0.18       // Ascending

        // Time windows (seconds)
        var windowSize: Int = 8
        var skiingConfirmWindow: Int = 5
        var liftConfirmWindow: Int = 5
        var stoppedConfirmWindow: Int = 8
        var debounceWindow: Int = 5

        // Minimum run duration (seconds)
        var minRunDuration: Double = 20.0

        // Require a clear downhill move before starting a new run.
        // 5.0 m ~= 16.4 ft
        var minRunStartDropMeters: Double = 5.0

        // Accuracy filter
        var maxAcceptableAccuracy: Double = 35.0

        // Vote threshold
        var voteThreshold: Double = 0.65
    }

    // MARK: - Published State

    @Published var currentState: SkiingState = .idle
    @Published var segments: [RunSegment] = []
    @Published var currentSegment: RunSegment?
    var onSegmentCompleted: ((RunSegment) -> Void)?

    // MARK: - Private State

    private var config = Config()
    private var sampleWindow: [LocationSample] = []
    private var lastStateChangeTime: Date?
    private var previousAltitude: Double?
    private var previousTimestamp: Date?

    // MARK: - Statistics

    var skiingRunCount: Int {
        segments.filter { $0.type == .skiing && $0.durationSeconds >= config.minRunDuration }.count
    }

    var liftCount: Int {
        segments.filter { $0.type == .lift }.count
    }

    var totalSkiingDistance: Double {
        segments.filter { $0.type == .skiing }.reduce(0) { $0 + $1.totalDistanceKm }
    }

    var totalVerticalDrop: Double {
        segments.filter { $0.type == .skiing }.reduce(0) { $0 + max(0, -$1.verticalChange) }
    }

    // MARK: - Public Methods

    func reset() {
        currentState = .idle
        segments = []
        currentSegment = nil
        sampleWindow = []
        lastStateChangeTime = nil
        previousAltitude = nil
        previousTimestamp = nil
    }

    func processLocation(_ location: CLLocation) {
        // Filter poor accuracy
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= config.maxAcceptableAccuracy else {
            return
        }

        // Calculate altitude change rate
        var altitudeChangeRate: Double = 0
        if let prevAlt = previousAltitude,
           let prevTime = previousTimestamp {
            let dt = location.timestamp.timeIntervalSince(prevTime)
            if dt > 0 {
                altitudeChangeRate = (location.altitude - prevAlt) / dt
            }
        }

        // Create sample
        let sample = LocationSample(
            location: location,
            timestamp: location.timestamp,
            speed: max(0, location.speed),
            altitude: location.altitude,
            altitudeChangeRate: altitudeChangeRate,
            horizontalAccuracy: location.horizontalAccuracy
        )

        // Add to window
        sampleWindow.append(sample)
        if sampleWindow.count > config.windowSize {
            sampleWindow.removeFirst()
        }

        // Update previous values
        previousAltitude = location.altitude
        previousTimestamp = location.timestamp

        // Add point to current segment
        let trackPoint = TrackPoint(from: location)
        if currentSegment != nil {
            currentSegment?.points.append(trackPoint)
        }

        // Analyze state
        if sampleWindow.count >= config.windowSize / 2 {
            analyzeAndUpdateState(currentTime: location.timestamp, trackPoint: trackPoint)
        }
    }

    // MARK: - State Analysis

    private func analyzeAndUpdateState(currentTime: Date, trackPoint: TrackPoint) {
        let detectedState = detectState()

        // Check debounce
        if let lastChange = lastStateChangeTime {
            let timeSinceLastChange = currentTime.timeIntervalSince(lastChange)
            if timeSinceLastChange < Double(config.debounceWindow) && currentState != .idle {
                // Still in debounce window, don't change state unless very confident
                return
            }
        }

        // Prevent over-sensitive run splitting:
        // only allow non-skiing -> skiing transition after clear altitude drop.
        if detectedState == .skiing,
           currentState != .skiing,
           !hasRequiredDropToStartRun(currentAltitude: trackPoint.altitude) {
            return
        }

        // State transition logic
        if detectedState != currentState {
            handleStateTransition(from: currentState, to: detectedState, at: currentTime, trackPoint: trackPoint)
        }
    }

    private func hasRequiredDropToStartRun(currentAltitude: Double) -> Bool {
        let requiredDrop = config.minRunStartDropMeters
        guard requiredDrop > 0 else { return true }

        // Use the highest altitude in the active non-skiing segment as the reference.
        if let segment = currentSegment, segment.type != .skiing, !segment.points.isEmpty {
            let referenceAltitude = segment.points.map(\.altitude).max() ?? currentAltitude
            return (referenceAltitude - currentAltitude) >= requiredDrop
        }

        // Fallback for startup/no active segment yet.
        guard !sampleWindow.isEmpty else { return false }
        let referenceAltitude = sampleWindow.map(\.altitude).max() ?? currentAltitude
        return (referenceAltitude - currentAltitude) >= requiredDrop
    }

    private func detectState() -> SkiingState {
        guard !sampleWindow.isEmpty else { return .idle }

        let speeds = sampleWindow.map { $0.speed }
        let altRates = sampleWindow.map { $0.altitudeChangeRate }

        let avgSpeed = speeds.reduce(0, +) / Double(speeds.count)
        let avgAltRate = altRates.reduce(0, +) / Double(altRates.count)

        // Count votes for each state
        var skiingVotes = 0
        var liftVotes = 0
        var stoppedVotes = 0

        for sample in sampleWindow {
            // Skiing: descending OR moving fast enough
            if sample.speed > config.skiingMinSpeed ||
               sample.altitudeChangeRate < config.skiingDescentRate {
                skiingVotes += 1
            }

            // Lift: ascending, optionally with low/moderate speed
            if sample.altitudeChangeRate > config.liftAscentRate &&
                sample.speed <= config.liftMaxSpeed {
                liftVotes += 1
            }

            // Stopped: very slow
            if sample.speed < config.stoppedMaxSpeed {
                stoppedVotes += 1
            }
        }

        let total = Double(sampleWindow.count)
        let skiingRatio = Double(skiingVotes) / total
        let liftRatio = Double(liftVotes) / total
        let stoppedRatio = Double(stoppedVotes) / total

        // Determine state by vote threshold
        if skiingRatio >= config.voteThreshold {
            return .skiing
        } else if liftRatio >= config.voteThreshold {
            return .lift
        } else if stoppedRatio >= config.voteThreshold {
            return .stopped
        }

        // Fallback: use averages
        if avgSpeed > config.skiingMinSpeed && avgAltRate < 0 {
            return .skiing
        } else if avgSpeed < config.stoppedMaxSpeed {
            return .stopped
        } else if avgAltRate > config.liftAscentRate {
            return .lift
        }

        return currentState // Keep current state if uncertain
    }

    private func handleStateTransition(from oldState: SkiingState, to newState: SkiingState, at time: Date, trackPoint: TrackPoint) {
        // Log state change
        let avgSpeed = sampleWindow.isEmpty ? 0 : sampleWindow.map { $0.speed }.reduce(0, +) / Double(sampleWindow.count)
        let avgAltRate = sampleWindow.isEmpty ? 0 : sampleWindow.map { $0.altitudeChangeRate }.reduce(0, +) / Double(sampleWindow.count)
        LoggingService.shared.logStateChange(
            from: oldState,
            to: newState,
            speed: avgSpeed,
            altitude: trackPoint.altitude,
            altitudeRate: avgAltRate
        )

        // End current segment
        if var segment = currentSegment {
            segment.endTime = time

            // Only save skiing segments that meet minimum duration
            if segment.type == .skiing {
                if segment.durationSeconds >= config.minRunDuration {
                    segments.append(segment)
                    DispatchQueue.main.async {
                        self.onSegmentCompleted?(segment)
                    }
                    LoggingService.shared.logRunCompleted(run: segment)
                }
            } else {
                segments.append(segment)
            }
        }

        // Start new segment
        currentSegment = RunSegment(type: newState, startTime: time)
        currentSegment?.points.append(trackPoint)

        currentState = newState
        lastStateChangeTime = time

        // Notify on main thread
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func finalizeCurrentSegment(forceIncludeCurrentSkiing: Bool = false) {
        if var segment = currentSegment {
            segment.endTime = Date()

            if segment.type == .skiing {
                let shouldSave = forceIncludeCurrentSkiing
                    ? segment.points.count > 1
                    : segment.durationSeconds >= config.minRunDuration
                if shouldSave {
                    segments.append(segment)
                    DispatchQueue.main.async {
                        self.onSegmentCompleted?(segment)
                    }
                }
            } else if segment.points.count > 0 {
                segments.append(segment)
            }

            currentSegment = nil
        }
    }

    // MARK: - Get Skiing Runs Only

    var skiingRuns: [RunSegment] {
        segments.filter { $0.type == .skiing && $0.durationSeconds >= config.minRunDuration }
    }

    // MARK: - Delete Run

    func deleteRun(id: UUID, reason: String = "User deleted") {
        if let index = segments.firstIndex(where: { $0.id == id }) {
            segments.remove(at: index)
            LoggingService.shared.logRunDeleted(runId: id, reason: reason)

            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}
