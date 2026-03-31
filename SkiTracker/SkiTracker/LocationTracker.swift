import Foundation
import CoreLocation
import Combine
import UIKit

// MARK: - LocationTracker

/// Wraps CLLocationManager to provide location tracking for skiing sessions.
/// Published properties drive SwiftUI updates.
final class LocationTracker: NSObject, ObservableObject {

    // MARK: - Published State

    /// Current authorization status
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether tracking is currently active
    @Published var isTracking: Bool = false

    /// Whether tracking is paused (session not ended)
    @Published var isPaused: Bool = false

    /// Raw CLLocation points collected during this session
    @Published var locations: [CLLocation] = []

    /// The current (latest) location
    @Published var currentLocation: CLLocation?

    /// Error message for UI display
    @Published var errorMessage: String?

    /// Run segmenter for automatic run detection
    @Published var segmenter = RunSegmenter()

    // MARK: - Private

    private let locationManager = CLLocationManager()

    /// Timestamp when tracking started
    private(set) var trackingStartDate: Date?

    // MARK: - Configuration Constants

    /// Production GPS quality filter for ski tracking.
    private let maxAcceptableAccuracy: Double = 35.0

    /// Balanced update frequency for outdoor skiing.
    private let defaultDistanceFilter: Double = 5.0

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        locationManager.distanceFilter = defaultDistanceFilter
        locationManager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = locationManager.authorizationStatus
    }

    /// Enable background location updates (call after authorization is granted)
    private func configureBackgroundUpdates() {
        let enabled = isTracking && !isPaused && authorizationStatus == .authorizedAlways
        locationManager.allowsBackgroundLocationUpdates = enabled
        locationManager.showsBackgroundLocationIndicator = enabled
    }

    // MARK: - Public Methods

    /// Request location permission (When In Use first)
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Request Always permission (for background tracking)
    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    /// Start recording location updates
    func startTracking() {
        guard !isTracking else { return }
        let strings = SettingsManager.shared.strings

        guard CLLocationManager.locationServicesEnabled() else {
            errorMessage = strings.locationServicesDisabled
            return
        }

        guard canTrack else {
            if authorizationStatus == .notDetermined {
                requestPermission()
            }
            errorMessage = strings.locationPermissionNeeded
            return
        }

        locations.removeAll()
        segmenter.reset()
        trackingStartDate = Date()
        isTracking = true
        isPaused = false
        errorMessage = nil
        configureBackgroundUpdates()
        locationManager.startUpdatingLocation()

        if authorizationStatus == .authorizedWhenInUse {
            requestAlwaysPermission()
            errorMessage = strings.locationBackgroundAccessRecommended
        }

        LoggingService.shared.logSessionStart()
    }

    /// Stop recording location updates
    func stopTracking() {
        guard isTracking else { return }
        locationManager.stopUpdatingLocation()
        isTracking = false
        isPaused = false
        configureBackgroundUpdates()
        // User explicitly stopped: persist an in-progress descending run even if not yet transitioned.
        segmenter.finalizeCurrentSegment(forceIncludeCurrentSkiing: true)

        LoggingService.shared.logSessionEnd(
            runCount: segmenter.skiingRunCount,
            liftCount: segmenter.liftCount,
            totalDistance: segmenter.totalSkiingDistance,
            totalVertical: segmenter.totalVerticalDrop
        )
    }

    /// Pause recording updates without ending current session.
    func pauseTracking() {
        guard isTracking, !isPaused else { return }
        locationManager.stopUpdatingLocation()
        isPaused = true
        configureBackgroundUpdates()
    }

    /// Resume recording updates for current session.
    func resumeTracking() {
        guard isTracking, isPaused else { return }
        isPaused = false
        configureBackgroundUpdates()
        locationManager.startUpdatingLocation()
    }

    /// Build a TrackSession from the current recorded data
    func buildSession() -> TrackSession {
        var session = TrackSession(
            startedAt: trackingStartDate ?? Date(),
            deviceInfo: UIDevice.current.model
        )
        session.endedAt = Date()
        session.points = locations.map { TrackPoint(from: $0) }
        session.segments = segmenter.segments
        return session
    }

    // MARK: - Helpers

    /// Check if authorization allows tracking
    var canTrack: Bool {
        authorizationStatus == .authorizedWhenInUse ||
        authorizationStatus == .authorizedAlways
    }

    /// Human-readable authorization status
    var authStatusDescription: String {
        switch authorizationStatus {
        case .notDetermined:    return "未请求"
        case .restricted:       return "受限"
        case .denied:           return "已拒绝 — 请前往设置开启定位"
        case .authorizedWhenInUse: return "使用时允许"
        case .authorizedAlways: return "始终允许"
        @unknown default:       return "未知"
        }
    }

    /// Dynamic distance filter based on speed (power saving)
    private func adjustDistanceFilter(for speed: Double) {
        let performanceMode = SettingsManager.shared.performanceModeEnabled
        if speed < 1.0 {
            locationManager.distanceFilter = 2.0
        } else if speed < 5.0 {
            locationManager.distanceFilter = 3.0
        } else {
            // High speed skiing: default 2m; Performance mode pushes to 1m for peak capture.
            locationManager.distanceFilter = performanceMode ? 1.0 : 2.0
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            self.configureBackgroundUpdates()
            if self.authorizationStatus == .authorizedAlways,
               self.errorMessage == SettingsManager.shared.strings.locationBackgroundAccessRecommended {
                self.errorMessage = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations newLocations: [CLLocation]) {
        guard isTracking, !isPaused else { return }

        if errorMessage != nil {
            DispatchQueue.main.async {
                self.errorMessage = nil
            }
        }

        for location in newLocations {
            // Filter: reject invalid accuracy
            guard location.horizontalAccuracy > 0,
                  location.horizontalAccuracy <= maxAcceptableAccuracy else {
                continue
            }

            // Adjust distance filter dynamically for power saving
            if location.speed >= 0 {
                adjustDistanceFilter(for: location.speed)
            }

            // Feed to segmenter for automatic run detection
            segmenter.processLocation(location)

            DispatchQueue.main.async {
                self.locations.append(location)
                self.currentLocation = location
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let strings = SettingsManager.shared.strings
        let clError = error as? CLError
        if clError?.code == .locationUnknown {
            return
        }

        DispatchQueue.main.async {
            guard let clError else {
                self.errorMessage = error.localizedDescription
                return
            }

            switch clError.code {
            case .denied:
                if self.isTracking {
                    self.stopTracking()
                }

                if self.authorizationStatus == .authorizedWhenInUse {
                    self.errorMessage = strings.locationBackgroundAccessRecommended
                } else {
                    self.errorMessage = strings.locationTrackingDenied
                }
            default:
                self.errorMessage = clError.localizedDescription
            }
        }
    }
}
