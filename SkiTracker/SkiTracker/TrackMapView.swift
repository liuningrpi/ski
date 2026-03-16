import SwiftUI
import MapKit

// MARK: - TrackMapView

/// Displays a map with the skiing track polyline and current position marker.
/// Uses UIViewRepresentable for reliable MKPolyline support across iOS versions.
struct TrackMapView: UIViewRepresentable {

    enum SegmentStyle: String {
        case skiing
        case lift
        case stopped
        case generic

        var color: UIColor {
            switch self {
            case .skiing: return .systemBlue
            case .lift: return .systemOrange
            case .stopped: return .systemGray
            case .generic: return .systemBlue
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .lift: return 5.5
            case .stopped: return 4.0
            case .skiing, .generic: return 4.5
            }
        }

        var lineDashPattern: [NSNumber]? {
            switch self {
            case .lift:
                // Dashed lift line improves visibility over overlapping ski tracks.
                return [8, 6]
            default:
                return nil
            }
        }
    }

    struct Segment: Identifiable {
        let id = UUID()
        let coordinates: [CLLocationCoordinate2D]
        let style: SegmentStyle
    }

    /// Array of coordinates to draw as a polyline
    let coordinates: [CLLocationCoordinate2D]

    /// Optional segmented track for style-aware rendering.
    let segments: [Segment]

    /// Whether to auto-follow the last point
    let followUser: Bool

    /// Whether to auto-fit the full route when not following.
    /// Keep this true for history detail pages; disable for live recording manual zoom/pan.
    let fitToRouteWhenNotFollowing: Bool

    /// Optional: show a marker at the last point
    let showEndMarker: Bool

    /// Increment this value to explicitly recenter map once.
    let recenterTrigger: Int

    /// Called when user manually interacts with the map (pan/zoom/rotate).
    let onUserInteraction: (() -> Void)?

    init(coordinates: [CLLocationCoordinate2D],
         followUser: Bool = true,
         fitToRouteWhenNotFollowing: Bool = true,
         showEndMarker: Bool = true,
         recenterTrigger: Int = 0,
         onUserInteraction: (() -> Void)? = nil) {
        self.coordinates = coordinates
        self.segments = []
        self.followUser = followUser
        self.fitToRouteWhenNotFollowing = fitToRouteWhenNotFollowing
        self.showEndMarker = showEndMarker
        self.recenterTrigger = recenterTrigger
        self.onUserInteraction = onUserInteraction
    }

    init(segments: [Segment],
         followUser: Bool = true,
         fitToRouteWhenNotFollowing: Bool = true,
         showEndMarker: Bool = true,
         recenterTrigger: Int = 0,
         onUserInteraction: (() -> Void)? = nil) {
        self.coordinates = []
        self.segments = segments
        self.followUser = followUser
        self.fitToRouteWhenNotFollowing = fitToRouteWhenNotFollowing
        self.showEndMarker = showEndMarker
        self.recenterTrigger = recenterTrigger
        self.onUserInteraction = onUserInteraction
    }

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.mapType = .standard
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = true
        mapView.isPitchEnabled = true
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onUserInteraction = onUserInteraction
        mapView.showsUserLocation = followUser
        context.coordinator.overlayStyles.removeAll()

        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        let displaySegments = effectiveSegments()
        let allCoordinates = displaySegments.flatMap { $0.coordinates }

        guard allCoordinates.count >= 2 else {
            // If we have a single point, center on it
            if let first = allCoordinates.first {
                let region = MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                mapView.setRegion(region, animated: true)
            }
            return
        }

        var combinedRect: MKMapRect = .null
        for segment in displaySegments where segment.coordinates.count >= 2 {
            let polyline = MKPolyline(coordinates: segment.coordinates, count: segment.coordinates.count)
            context.coordinator.overlayStyles[ObjectIdentifier(polyline)] = segment.style
            mapView.addOverlay(polyline)
            combinedRect = combinedRect.isNull ? polyline.boundingMapRect : combinedRect.union(polyline.boundingMapRect)
        }

        // Add end marker
        if showEndMarker, let last = allCoordinates.last {
            let annotation = MKPointAnnotation()
            annotation.coordinate = last
            annotation.title = SettingsManager.shared.strings.currentLocation
            mapView.addAnnotation(annotation)
        }

        let shouldRecenter = recenterTrigger != context.coordinator.lastRecenterTrigger
        if shouldRecenter {
            context.coordinator.lastRecenterTrigger = recenterTrigger
        }

        if (followUser || shouldRecenter), let last = allCoordinates.last {
            // Auto-follow last point for live tracking
            let region = MKCoordinateRegion(
                center: last,
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            )
            mapView.setRegion(region, animated: true)
        } else if fitToRouteWhenNotFollowing {
            // Fit historic route into viewport so the run is centered and readable.
            if !combinedRect.isNull && !combinedRect.isEmpty {
                mapView.setVisibleMapRect(
                    combinedRect,
                    edgePadding: UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24),
                    animated: true
                )
            }
        }
    }

    private func effectiveSegments() -> [Segment] {
        if !segments.isEmpty {
            return segments
        }
        guard !coordinates.isEmpty else { return [] }
        return [Segment(coordinates: coordinates, style: .generic)]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {
        var lastRecenterTrigger: Int = 0
        var onUserInteraction: (() -> Void)?
        var overlayStyles: [ObjectIdentifier: TrackMapView.SegmentStyle] = [:]

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let style = overlayStyles[ObjectIdentifier(polyline)] ?? .generic
                renderer.strokeColor = style.color
                renderer.lineWidth = style.lineWidth
                renderer.lineDashPattern = style.lineDashPattern
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            // Don't customize user location
            if annotation is MKUserLocation { return nil }

            let identifier = "EndMarker"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view?.canShowCallout = true
            } else {
                view?.annotation = annotation
            }
            view?.markerTintColor = .systemRed
            view?.glyphImage = UIImage(systemName: "figure.skiing.downhill")
            return view
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            // Detect gesture-driven region changes so parent can stop auto-follow.
            let interacted = mapView.subviews
                .compactMap { $0.gestureRecognizers }
                .flatMap { $0 }
                .contains { recognizer in
                    recognizer.state == .began || recognizer.state == .changed
                }
            if interacted {
                onUserInteraction?()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TrackMapView(
        coordinates: [
            CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            CLLocationCoordinate2D(latitude: 39.9052, longitude: 116.4084),
            CLLocationCoordinate2D(latitude: 39.9062, longitude: 116.4094),
        ],
        followUser: true,
        showEndMarker: true
    )
}
