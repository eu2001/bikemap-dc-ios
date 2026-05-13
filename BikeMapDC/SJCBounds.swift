import CoreLocation

/// Geographic boundary for BikeMap DC.
///
/// Mirrors the coverage of the official goDCgo "DC Bike Map" — Washington, D.C.
/// plus the immediate metro region shown on that map:
///  - North: Bethesda / Silver Spring (MD)
///  - South: Old Town Alexandria / Huntington (VA)
///  - West: Tysons / McLean / Arlington / Falls Church (VA)
///  - East: New Carrollton / Capitol Heights / Suitland (MD)
enum DCBounds {
    // Regional bounding box (matches goDCgo DC Bike Map coverage)
    private static let minLat: Double = 38.76   // Alexandria south
    private static let maxLat: Double = 39.05   // Silver Spring / Bethesda
    private static let minLon: Double = -77.27  // Tysons / McLean
    private static let maxLon: Double = -76.80  // New Carrollton / Suitland

    /// Returns `true` if the coordinate falls within D.C.
    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude  >= minLat &&
        coordinate.latitude  <= maxLat &&
        coordinate.longitude >= minLon &&
        coordinate.longitude <= maxLon
    }

    /// Center of the District (approximately, near the National Mall).
    static let defaultCenter = CLLocationCoordinate2D(
        latitude: 38.9072,
        longitude: -77.0369
    )

    /// Localized message shown when a point falls outside the supported area.
    /// Spanish translation is provided in `Localizable.xcstrings`.
    static var outOfBoundsMessage: String {
        String(localized: "This point is outside the DC bike-map area. Please choose a location within the metro region.")
    }
}

/// Back-compat alias so call sites that still reference `SJCBounds` keep
/// compiling during the SJC → DC rename. Prefer `DCBounds` in new code.
typealias SJCBounds = DCBounds
