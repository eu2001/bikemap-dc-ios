import SwiftUI
import MapKit
import CoreLocation

// MARK: - UIViewRepresentable

struct BikeMapView: UIViewRepresentable {
    @ObservedObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false

        // Initial region: Washington, D.C.
        let center = DCBounds.defaultCenter
        mapView.setRegion(MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.12, longitudeDelta: 0.12)), animated: false)

        // Map tap for picking mode
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        context.coordinator.setupInfra()
        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let c = context.coordinator
        // Reload infra polylines if Supabase data just arrived
        if !appState.infraFeatures.isEmpty && c.infraLoadedFromSupabase == false {
            c.infraLoadedFromSupabase = true
            c.reloadInfra(mapView: mapView)
        }
        c.syncInfra(mapView: mapView, visibility: appState.layerVisibility)
        c.syncPOIs(mapView: mapView, pois: appState.pois, visibility: appState.layerVisibility)

        if appState.shouldCenterOnUser {
            if let userCoord = mapView.userLocation.location?.coordinate {
                mapView.setCenter(userCoord, animated: true)
            }
            DispatchQueue.main.async { self.appState.shouldCenterOnUser = false }
        }

        if appState.zoomDelta != 0 {
            var region = mapView.region
            let factor = appState.zoomDelta > 0 ? 0.5 : 2.0
            region.span.latitudeDelta  = min(max(region.span.latitudeDelta  * factor, 0.002), 60)
            region.span.longitudeDelta = min(max(region.span.longitudeDelta * factor, 0.002), 60)
            mapView.setRegion(region, animated: true)
            DispatchQueue.main.async { self.appState.zoomDelta = 0 }
        }
    }
}

// MARK: - Coordinator

final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate,
                         CLLocationManagerDelegate {
    weak var mapView: MKMapView?
    var appState: AppState

    // Infra overlays, keyed by InfraType.rawValue
    private var infraPolylines: [String: [BikePolyline]] = [:]
    private var infraOnMap: Set<String> = []
    var infraLoadedFromSupabase = false

    // POI annotations, keyed by poi.id
    private var poiAnnotations: [String: POIAnnotation] = [:]

    // Initial centering on user
    private var didCenterOnUser = false
    private let locationManager = CLLocationManager()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.requestWhenInUseAuthorization()
    }

    // Called when permission is granted (or already granted) — start getting location
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    // Called with a single location fix — center the map once, then stop
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !didCenterOnUser, let loc = locations.last else { return }
        didCenterOnUser = true
        manager.stopUpdatingLocation()
        DispatchQueue.main.async { [weak self] in
            guard let mv = self?.mapView else { return }
            // ~100 m de raio ao redor do usuário (região de 200 m × 200 m)
            let region = MKCoordinateRegion(center: loc.coordinate,
                                            latitudinalMeters: 200,
                                            longitudinalMeters: 200)
            mv.setRegion(region, animated: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently fall back to the default SJC view
    }

    // MKMapView also calls this delegate — keep as a safety net
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        // Keep AppState's `lastKnownUserLocation` in sync so the 5-mile
        // contribution gate works.
        if let loc = userLocation.location {
            DispatchQueue.main.async {
                self.appState.lastKnownUserLocation = loc.coordinate
            }
        }
        guard !didCenterOnUser, let loc = userLocation.location else { return }
        didCenterOnUser = true
        let region = MKCoordinateRegion(center: loc.coordinate,
                                        latitudinalMeters: 200,
                                        longitudinalMeters: 200)
        mapView.setRegion(region, animated: true)
    }

    // MARK: Setup

    func reloadInfra(mapView: MKMapView) {
        // Remove all existing infra overlays from the map
        let toRemove = infraPolylines.values.flatMap { $0 }
        mapView.removeOverlays(toRemove)
        infraPolylines = [:]
        infraOnMap = []
        // Rebuild from Supabase data
        setupInfra()
    }

    func setupInfra() {
        let features = appState.infraFeatures.isEmpty ? MapData.infraFeatures : appState.infraFeatures
        for feature in features {
            let pl = BikePolyline(coordinates: feature.coordinates, count: feature.coordinates.count)
            pl.infraType = feature.type
            pl.featureName = feature.name
            pl.extensionKm = feature.extensionKm
            pl.reason = feature.reason
            pl.status = feature.status
            pl.forecast = feature.forecast
            infraPolylines[feature.type.rawValue, default: []].append(pl)
        }
    }

    // MARK: Sync methods

    func syncInfra(mapView: MKMapView, visibility: [String: Bool]) {
        for type in InfraType.allCases {
            let key = type.rawValue
            let shouldShow = visibility[key] ?? false
            let onMap = infraOnMap.contains(key)
            let polylines = infraPolylines[key] ?? []

            if shouldShow && !onMap {
                polylines.forEach { mapView.addOverlay($0, level: .aboveRoads) }
                infraOnMap.insert(key)
            } else if !shouldShow && onMap {
                polylines.forEach { mapView.removeOverlay($0) }
                infraOnMap.remove(key)
            }
        }
    }

    func syncPOIs(mapView: MKMapView, pois: [POI], visibility: [String: Bool]) {
        for poi in pois where poiAnnotations[poi.id] == nil {
            poiAnnotations[poi.id] = POIAnnotation(poi: poi)
        }

        let onMapIds = Set(mapView.annotations.compactMap { ($0 as? POIAnnotation)?.poi.id })

        for (poiId, ann) in poiAnnotations {
            let shouldShow = visibility[ann.poi.type] ?? false
            let onMap = onMapIds.contains(poiId)
            if shouldShow && !onMap {
                mapView.addAnnotation(ann)
            } else if !shouldShow && onMap {
                mapView.removeAnnotation(ann)
            }
        }
    }

    // MARK: Map tap

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let mapView else { return }
        let point = gesture.location(in: mapView)
        let coord = mapView.convert(point, toCoordinateFrom: mapView)

        switch appState.mapPickingMode {
        case .addPoint:
            DispatchQueue.main.async {
                self.appState.pendingAddCoordinate = coord
                self.appState.mapPickingMode = nil
                self.appState.showAddPoint = true
            }
        case .none:
            break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        appState.mapPickingMode != nil
    }

    // MARK: MKMapViewDelegate – overlay renderer

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let bike = overlay as? BikePolyline {
            let r = MKPolylineRenderer(polyline: bike)
            r.strokeColor = bike.infraType.uiColor
            r.lineWidth   = bike.infraType.lineWidth
            r.alpha       = 0.88
            r.lineDashPattern = bike.infraType.dashPattern
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    // MARK: MKMapViewDelegate – annotation views

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }

        if let poiAnn = annotation as? POIAnnotation {
            let reuseId = "poi_\(poiAnn.poi.type)"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseId)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            view.annotation = annotation
            view.image = makeEmojiImage(poiAnn.poi.poiType.emoji, borderColor: poiAnn.poi.poiType.uiColor)
            view.canShowCallout = false; view.centerOffset = .zero
            return view
        }

        return nil
    }

    func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
        mapView.deselectAnnotation(annotation, animated: false)
        guard appState.mapPickingMode == nil else { return }
        if let poiAnn = annotation as? POIAnnotation {
            DispatchQueue.main.async { self.appState.selectedPOI = poiAnn.poi }
        }
    }

    // MARK: Emoji image helper

    private func makeEmojiImage(_ emoji: String, borderColor: UIColor = .systemRed) -> UIImage {
        let size: CGFloat = 30
        let borderWidth: CGFloat = 2.0
        let renderer = UIGraphicsImageRenderer(size: .init(width: size, height: size))
        return renderer.image { _ in
            let circle = UIBezierPath(ovalIn: .init(x: 0, y: 0, width: size, height: size))

            // White fill
            UIColor.white.setFill()
            circle.fill()

            // Coloured border
            borderColor.setStroke()
            circle.lineWidth = borderWidth
            circle.stroke()

            // Emoji
            let font = UIFont.systemFont(ofSize: size * 0.50)
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (emoji as NSString).size(withAttributes: attrs)
            let origin = CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2)
            (emoji as NSString).draw(at: origin, withAttributes: attrs)
        }
    }
}

