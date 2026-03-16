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
        SkiMetrics.totalDistanceMeters(points: points)
    }

    var totalDistanceKm: Double {
        totalDistanceMeters / 1000.0
    }

    var maxSpeedKmh: Double {
        SkiMetrics.peakSpeedKmh(points: points)
    }

    var avgSpeedKmh: Double {
        SkiMetrics.averageSpeedKmh(points: points)
    }

    var elevationDrop: Double {
        guard let maxAlt = points.map({ $0.altitude }).max(),
              let minAlt = points.map({ $0.altitude }).min() else { return 0 }
        return maxAlt - minAlt
    }

    /// Cumulative descent on smoothed altitude series (meters).
    var cumulativeDescent: Double {
        guard points.count >= 2 else { return 0 }
        let smoothed = smoothedAltitudes()
        guard smoothed.count >= 2 else { return 0 }

        var total: Double = 0
        for i in 1..<smoothed.count {
            let drop = smoothed[i - 1] - smoothed[i]
            if drop > 0 {
                total += drop
            }
        }
        return total
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

    private func smoothedAltitudes(alpha: Double = 0.35) -> [Double] {
        guard !points.isEmpty else { return [] }
        var result: [Double] = []
        result.reserveCapacity(points.count)

        var ema = points[0].altitude
        result.append(ema)
        for point in points.dropFirst() {
            ema = alpha * point.altitude + (1 - alpha) * ema
            result.append(ema)
        }
        return result
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
        var liftStopHoldAscentFloor: Double = -0.08 // Treat near-flat slope as lift while already on lift

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

        // Merge adjacent skiing segments if they are split by a short non-lift interruption.
        var maxRunMergeGapSeconds: Double = 45.0
        var maxRunMergeInterruptionAscentMeters: Double = 4.0

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
        segments.filter { $0.type == .skiing }.reduce(0) { $0 + $1.cumulativeDescent }
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
            let isAscending = sample.altitudeChangeRate > config.liftAscentRate

            // Ascending segments should strongly favor lift, even when horizontal speed is high.
            if isAscending && sample.speed <= config.liftMaxSpeed {
                liftVotes += 1
            }

            // If already on lift, temporary stop/slow queue should remain part of lift.
            if currentState == .lift,
               sample.speed <= config.stoppedMaxSpeed,
               sample.altitudeChangeRate >= config.liftStopHoldAscentFloor {
                liftVotes += 1
            }

            // Skiing: descending OR moving fast enough
            if !isAscending && (sample.speed > config.skiingMinSpeed ||
               sample.altitudeChangeRate < config.skiingDescentRate) {
                skiingVotes += 1
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

        // Keep lift continuity during temporary stalls/queues.
        if currentState == .lift,
           skiingRatio < config.voteThreshold,
           avgAltRate >= config.liftStopHoldAscentFloor {
            return .lift
        }

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
            persistCompletedSegment(segment, forceIncludeCurrentSkiing: false)
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
            persistCompletedSegment(segment, forceIncludeCurrentSkiing: forceIncludeCurrentSkiing)

            currentSegment = nil
        }
    }

    private func persistCompletedSegment(_ segment: RunSegment, forceIncludeCurrentSkiing: Bool) {
        if segment.type == .skiing {
            let shouldSave = forceIncludeCurrentSkiing
                ? segment.points.count > 1
                : segment.durationSeconds >= config.minRunDuration
            guard shouldSave else { return }

            if mergeIntoPreviousSkiingIfNeeded(segment) {
                return
            }

            segments.append(segment)
            DispatchQueue.main.async {
                self.onSegmentCompleted?(segment)
            }
            LoggingService.shared.logRunCompleted(run: segment)
            return
        }

        if segment.points.count > 0 {
            segments.append(segment)
        }
    }

    private func mergeIntoPreviousSkiingIfNeeded(_ newSkiingSegment: RunSegment) -> Bool {
        guard !segments.isEmpty else { return false }

        var idx = segments.count - 1
        var interruption: [RunSegment] = []

        while idx >= 0, segments[idx].type != .skiing {
            interruption.insert(segments[idx], at: 0)
            if idx == 0 { break }
            idx -= 1
        }

        guard idx >= 0, segments[idx].type == .skiing else { return false }
        let previousSkiing = segments[idx]

        if interruption.contains(where: { $0.type == .lift }) {
            return false
        }

        let interruptionDuration = interruption.reduce(0.0) { $0 + $1.durationSeconds }
        if interruptionDuration > config.maxRunMergeGapSeconds {
            return false
        }

        let interruptionPoints = interruption.flatMap { $0.points }
        if let firstAlt = interruptionPoints.first?.altitude,
           let maxAlt = interruptionPoints.map(\.altitude).max(),
           (maxAlt - firstAlt) > config.maxRunMergeInterruptionAscentMeters {
            return false
        }

        var merged = previousSkiing
        merged.endTime = newSkiingSegment.endTime
        var mergedPoints = previousSkiing.points
        mergedPoints.append(contentsOf: interruptionPoints)
        mergedPoints.append(contentsOf: newSkiingSegment.points)
        merged.points = mergedPoints

        segments.removeSubrange(idx..<segments.count)
        segments.append(merged)
        return true
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
