import SwiftUI
import MapKit

// MARK: - TrackMapView

/// Displays a map with the skiing track polyline and current position marker.
/// Uses UIViewRepresentable for reliable MKPolyline support across iOS versions.
struct TrackMapView: UIViewRepresentable {

    struct RenderStyle {
        let color: UIColor
        let lineWidth: CGFloat
        let lineDashPattern: [NSNumber]?
        let drawPriority: Int
    }

    enum SegmentStyle: String {
        case skiing
        case lift
        case stopped
        case generic

        var color: UIColor {
            switch self {
            case .skiing: return .systemBlue
            case .lift: return .systemYellow
            case .stopped: return .systemGray
            case .generic: return .systemBlue
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .lift: return 4.5
            case .stopped: return 4.0
            case .skiing, .generic: return 4.5
            }
        }

        var lineDashPattern: [NSNumber]? {
            switch self {
            case .lift:
                return nil
            default:
                return nil
            }
        }

        var drawPriority: Int {
            switch self {
            case .skiing, .generic: return 0
            case .stopped: return 1
            case .lift: return 2
            }
        }
    }

    struct Segment: Identifiable {
        let id = UUID()
        let coordinates: [CLLocationCoordinate2D]
        let style: SegmentStyle

        /// Optional style overrides for views that need per-segment coloring (e.g. speed heatmap).
        let colorOverride: UIColor?
        let lineWidthOverride: CGFloat?
        let lineDashPatternOverride: [NSNumber]?
        let drawPriorityOverride: Int

        init(
            coordinates: [CLLocationCoordinate2D],
            style: SegmentStyle,
            colorOverride: UIColor? = nil,
            lineWidthOverride: CGFloat? = nil,
            lineDashPatternOverride: [NSNumber]? = nil,
            drawPriorityOverride: Int? = nil
        ) {
            self.coordinates = coordinates
            self.style = style
            self.colorOverride = colorOverride
            self.lineWidthOverride = lineWidthOverride
            self.lineDashPatternOverride = lineDashPatternOverride
            self.drawPriorityOverride = drawPriorityOverride ?? style.drawPriority
        }

        var renderStyle: RenderStyle {
            RenderStyle(
                color: colorOverride ?? style.color,
                lineWidth: lineWidthOverride ?? style.lineWidth,
                lineDashPattern: lineDashPatternOverride ?? style.lineDashPattern,
                drawPriority: drawPriorityOverride
            )
        }
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

    /// Optional moving marker used by run playback in detail views.
    let playbackCoordinate: CLLocationCoordinate2D?
    let playbackInitials: String?
    let playbackPhotoURL: URL?

    init(coordinates: [CLLocationCoordinate2D],
         followUser: Bool = true,
         fitToRouteWhenNotFollowing: Bool = true,
         showEndMarker: Bool = true,
         recenterTrigger: Int = 0,
         onUserInteraction: (() -> Void)? = nil,
         playbackCoordinate: CLLocationCoordinate2D? = nil,
         playbackInitials: String? = nil,
         playbackPhotoURL: URL? = nil) {
        self.coordinates = coordinates
        self.segments = []
        self.followUser = followUser
        self.fitToRouteWhenNotFollowing = fitToRouteWhenNotFollowing
        self.showEndMarker = showEndMarker
        self.recenterTrigger = recenterTrigger
        self.onUserInteraction = onUserInteraction
        self.playbackCoordinate = playbackCoordinate
        self.playbackInitials = playbackInitials
        self.playbackPhotoURL = playbackPhotoURL
    }

    init(segments: [Segment],
         followUser: Bool = true,
         fitToRouteWhenNotFollowing: Bool = true,
         showEndMarker: Bool = true,
         recenterTrigger: Int = 0,
         onUserInteraction: (() -> Void)? = nil,
         playbackCoordinate: CLLocationCoordinate2D? = nil,
         playbackInitials: String? = nil,
         playbackPhotoURL: URL? = nil) {
        self.coordinates = []
        self.segments = segments
        self.followUser = followUser
        self.fitToRouteWhenNotFollowing = fitToRouteWhenNotFollowing
        self.showEndMarker = showEndMarker
        self.recenterTrigger = recenterTrigger
        self.onUserInteraction = onUserInteraction
        self.playbackCoordinate = playbackCoordinate
        self.playbackInitials = playbackInitials
        self.playbackPhotoURL = playbackPhotoURL
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

        let routeSignature = signature(for: displaySegments)
        var combinedRect = context.coordinator.lastCombinedRect

        if routeSignature != context.coordinator.lastRouteSignature {
            context.coordinator.lastRouteSignature = routeSignature
            mapView.removeOverlays(mapView.overlays)

            let sortedSegments = displaySegments.sorted { $0.renderStyle.drawPriority < $1.renderStyle.drawPriority }
            combinedRect = .null
            for segment in sortedSegments where segment.coordinates.count >= 2 {
                let polyline = MKPolyline(coordinates: segment.coordinates, count: segment.coordinates.count)
                context.coordinator.overlayStyles[ObjectIdentifier(polyline)] = segment.renderStyle
                mapView.addOverlay(polyline)
                combinedRect = combinedRect.isNull ? polyline.boundingMapRect : combinedRect.union(polyline.boundingMapRect)
            }
            context.coordinator.lastCombinedRect = combinedRect
        }

        // Keep only one end marker; do not remove playback marker each frame.
        let allNonUser = mapView.annotations.filter { !($0 is MKUserLocation) }
        let endMarkers = allNonUser.filter { !($0 is PlaybackAnnotation) }
        if !endMarkers.isEmpty {
            mapView.removeAnnotations(endMarkers)
        }

        if showEndMarker, let last = allCoordinates.last {
            let end = MKPointAnnotation()
            end.coordinate = last
            end.title = SettingsManager.shared.strings.currentLocation
            mapView.addAnnotation(end)
        }

        // Update playback marker in place for smooth animation and reliable visibility.
        let existingPlayback = allNonUser.compactMap { $0 as? PlaybackAnnotation }.first
        if let playbackCoordinate {
            if let existingPlayback {
                existingPlayback.coordinate = playbackCoordinate
                existingPlayback.initials = playbackInitials
                existingPlayback.photoURL = playbackPhotoURL
                if let view = mapView.view(for: existingPlayback) as? PlaybackAvatarAnnotationView {
                    view.configure(with: existingPlayback)
                }
            } else {
                let annotation = PlaybackAnnotation()
                annotation.coordinate = playbackCoordinate
                annotation.initials = playbackInitials
                annotation.photoURL = playbackPhotoURL
                mapView.addAnnotation(annotation)
            }
        } else if let existingPlayback {
            mapView.removeAnnotation(existingPlayback)
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
            let needsRefit = routeSignature != context.coordinator.lastFittedRouteSignature || shouldRecenter
            if needsRefit, !combinedRect.isNull && !combinedRect.isEmpty {
                context.coordinator.lastFittedRouteSignature = routeSignature
                mapView.setVisibleMapRect(
                    combinedRect,
                    edgePadding: UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24),
                    animated: true
                )
            }
        }
    }

    private func signature(for segments: [Segment]) -> Int {
        var hasher = Hasher()
        hasher.combine(segments.count)
        for segment in segments {
            hasher.combine(segment.coordinates.count)
            if let first = segment.coordinates.first {
                hasher.combine(Int(first.latitude * 10000))
                hasher.combine(Int(first.longitude * 10000))
            }
            if let last = segment.coordinates.last {
                hasher.combine(Int(last.latitude * 10000))
                hasher.combine(Int(last.longitude * 10000))
            }
            hasher.combine(segment.renderStyle.drawPriority)
            hasher.combine(Int(segment.renderStyle.lineWidth * 10))
        }
        return hasher.finalize()
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
        var lastRouteSignature: Int?
        var lastFittedRouteSignature: Int?
        var lastCombinedRect: MKMapRect = .null
        var onUserInteraction: (() -> Void)?
        var overlayStyles: [ObjectIdentifier: TrackMapView.RenderStyle] = [:]

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                let style = overlayStyles[ObjectIdentifier(polyline)] ?? RenderStyle(
                    color: UIColor.systemBlue,
                    lineWidth: 4.5,
                    lineDashPattern: nil,
                    drawPriority: 0
                )
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

            if let playback = annotation as? PlaybackAnnotation {
                let identifier = "PlaybackAvatar"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? PlaybackAvatarAnnotationView
                if view == nil {
                    view = PlaybackAvatarAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                } else {
                    view?.annotation = annotation
                }
                view?.configure(with: playback)
                return view
            }

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

    final class PlaybackAnnotation: MKPointAnnotation {
        var initials: String?
        var photoURL: URL?
    }

    final class PlaybackAvatarAnnotationView: MKAnnotationView {
        private static let imageCache = NSCache<NSURL, UIImage>()

        private let container = UIView()
        private let imageView = UIImageView()
        private let initialsBadge = UILabel()
        private let fallbackInitials = UILabel()
        private var currentImageURL: URL?

        override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
            super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
            setupUI()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupUI()
        }

        private func setupUI() {
            frame = CGRect(x: 0, y: 0, width: 42, height: 42)
            centerOffset = CGPoint(x: 0, y: -8)
            canShowCallout = false
            collisionMode = .circle

            container.frame = bounds
            container.backgroundColor = .systemBlue
            container.layer.cornerRadius = bounds.width / 2
            container.layer.borderColor = UIColor.white.cgColor
            container.layer.borderWidth = 2
            container.clipsToBounds = true

            imageView.frame = container.bounds
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isHidden = true

            fallbackInitials.frame = container.bounds
            fallbackInitials.textAlignment = .center
            fallbackInitials.font = UIFont.systemFont(ofSize: 16, weight: .bold)
            fallbackInitials.textColor = .white

            initialsBadge.frame = CGRect(x: bounds.width - 18, y: bounds.height - 18, width: 16, height: 16)
            initialsBadge.textAlignment = .center
            initialsBadge.font = UIFont.systemFont(ofSize: 9, weight: .bold)
            initialsBadge.textColor = .white
            initialsBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
            initialsBadge.layer.cornerRadius = 8
            initialsBadge.clipsToBounds = true
            initialsBadge.isHidden = true

            addSubview(container)
            container.addSubview(imageView)
            container.addSubview(fallbackInitials)
            addSubview(initialsBadge)
        }

        func configure(with annotation: PlaybackAnnotation) {
            let initials = annotation.initials?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayInitials = (initials?.isEmpty == false ? initials! : "U")
            fallbackInitials.text = displayInitials
            initialsBadge.text = displayInitials

            if let url = annotation.photoURL {
                loadImage(from: url)
            } else {
                currentImageURL = nil
                imageView.isHidden = true
                fallbackInitials.isHidden = false
                initialsBadge.isHidden = true
            }
        }

        private func loadImage(from url: URL) {
            currentImageURL = url
            let key = url as NSURL
            if let cached = Self.imageCache.object(forKey: key) {
                applyLoadedImage(cached, for: url)
                return
            }

            imageView.isHidden = true
            fallbackInitials.isHidden = false
            initialsBadge.isHidden = true

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data) else { return }
                Self.imageCache.setObject(image, forKey: key)
                DispatchQueue.main.async {
                    self.applyLoadedImage(image, for: url)
                }
            }.resume()
        }

        private func applyLoadedImage(_ image: UIImage, for url: URL) {
            guard currentImageURL == url else { return }
            imageView.image = image
            imageView.isHidden = false
            fallbackInitials.isHidden = true
            initialsBadge.isHidden = false
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
