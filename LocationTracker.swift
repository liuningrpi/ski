import Foundation
import CoreLocation
import Combine

// MARK: - LocationTracker

/// Wraps CLLocationManager to provide location tracking for skiing sessions.
/// Published properties drive SwiftUI updates.
final class LocationTracker: NSObject, ObservableObject {

    // MARK: - Published State

    /// Current authorization status
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Whether tracking is currently active
    @Published var isTracking: Bool = false

    /// Raw CLLocation points collected during this session
    @Published var locations: [CLLocation] = []

    /// The current (latest) location
    @Published var currentLocation: CLLocation?

    /// Error message for UI display
    @Published var errorMessage: String?

    // MARK: - Private

    private let locationManager = CLLocationManager()

    /// Timestamp when tracking started
    private(set) var trackingStartDate: Date?

    // MARK: - Configuration Constants

    /// Minimum horizontal accuracy to accept a point (meters)
    private let maxAcceptableAccuracy: Double = 20.0

    /// Distance filter in meters (minimum movement to trigger update)
    private let defaultDistanceFilter: Double = 5.0

    // MARK: - Init

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        locationManager.distanceFilter = defaultDistanceFilter
        // Background support (V1.1)
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        authorizationStatus = locationManager.authorizationStatus
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
        locations.removeAll()
        trackingStartDate = Date()
        isTracking = true
        errorMessage = nil
        locationManager.startUpdatingLocation()
    }

    /// Stop recording location updates
    func stopTracking() {
        guard isTracking else { return }
        locationManager.stopUpdatingLocation()
        isTracking = false
    }

    /// Build a TrackSession from the current recorded data
    func buildSession() -> TrackSession {
        var session = TrackSession(
            startedAt: trackingStartDate ?? Date(),
            deviceInfo: UIDevice.current.model
        )
        session.endedAt = Date()
        session.points = locations.map { TrackPoint(from: $0) }
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
        if speed < 1.0 {
            // Nearly stationary — reduce updates
            locationManager.distanceFilter = 10.0
        } else if speed < 5.0 {
            locationManager.distanceFilter = 5.0
        } else {
            // High speed skiing — fine-grained tracking
            locationManager.distanceFilter = 3.0
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationTracker: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations newLocations: [CLLocation]) {
        guard isTracking else { return }

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

            DispatchQueue.main.async {
                self.locations.append(location)
                self.currentLocation = location
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
        }
    }
}
