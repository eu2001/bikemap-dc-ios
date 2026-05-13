import Foundation
import MapKit

// MARK: - Map data
//
// For BikeMap DC, bike infrastructure features and POIs are loaded
// dynamically from Supabase (DDOT bike lanes + user contributions).
// This file keeps the `MapData` namespace for back-compat with call
// sites that still reference fallback arrays, but ships them empty.

enum MapData {

    /// Fallback infrastructure features. Empty for DC — real data lives in
    /// the Supabase `infra_features` table and is loaded into
    /// `AppState.infraFeatures` at launch.
    static let infraFeatures: [BikeInfraFeature] = []

    /// Fallback POIs. Empty for DC — real data comes from Supabase.
    static let initialPOIs: [POI] = []
}
