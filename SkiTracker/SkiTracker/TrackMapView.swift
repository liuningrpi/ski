import SwiftUI
import MapKit

// MARK: - TrackMapView

/// Displays a map with the skiing track polyline and current position marker.
/// Uses UIViewRepresentable for reliable MKPolyline support across iOS versions.
struct TrackMapView: UIViewRepresentable {

    /// Array of coordinates to draw as a polyline
    let coordinates: [CLLocationCoordinate2D]

    /// Whether to auto-follow the last point
    let followUser: Bool

    /// Optional: show a marker at the last point
    let showEndMarker: Bool

    init(coordinates: [CLLocationCoordinate2D],
         followUser: Bool = true,
         showEndMarker: Bool = true) {
        self.coordinates = coordinates
        self.followUser = followUser
        self.showEndMarker = showEndMarker
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
        mapView.showsUserLocation = followUser

        // Remove old overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

        guard coordinates.count >= 2 else {
            // If we have a single point, center on it
            if let first = coordinates.first {
                let region = MKCoordinateRegion(
                    center: first,
                    latitudinalMeters: 1000,
                    longitudinalMeters: 1000
                )
                mapView.setRegion(region, animated: true)
            }
            return
        }

        // Draw polyline
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)

        // Add end marker
        if showEndMarker, let last = coordinates.last {
            let annotation = MKPointAnnotation()
            annotation.coordinate = last
            annotation.title = SettingsManager.shared.strings.currentLocation
            mapView.addAnnotation(annotation)
        }

        if followUser, let last = coordinates.last {
            // Auto-follow last point for live tracking
            let region = MKCoordinateRegion(
                center: last,
                latitudinalMeters: 1200,
                longitudinalMeters: 1200
            )
            mapView.setRegion(region, animated: true)
        } else {
            // Fit historic route into viewport so the run is centered and readable.
            let rect = polyline.boundingMapRect
            if !rect.isNull && !rect.isEmpty {
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24),
                    animated: true
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MKMapViewDelegate {

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 4.0
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
