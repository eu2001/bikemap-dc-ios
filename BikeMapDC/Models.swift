import Foundation
import MapKit
import SwiftUI

// MARK: - Infrastructure Types

/// DC Bike Map cycle-route categories, mirroring the official legend.
/// Order here drives the legend / Layers panel display order.
enum InfraType: String, CaseIterable, Codable {
    case protected_lane        // double dark-green line
    case bike_lane             // solid dark line
    case contraflow_lane       // dark line with tick marks
    case bus_bike_lane         // dotted/rect pattern
    case shared_lane           // sharrow — medium dashes
    case signed_route          // on-street signed route — small dots
    case off_street_trail      // double light-green line in legend
    case unpaved_trail         // dashed brown
    case mountain_bike_trail   // dashed purple

    var uiColor: UIColor {
        switch self {
        case .off_street_trail:     return .init(red: 0.45, green: 0.78, blue: 0.45, alpha: 1) // light green
        case .protected_lane:       return .init(red: 0.12, green: 0.55, blue: 0.20, alpha: 1) // dark green
        case .contraflow_lane:      return .init(red: 0.20, green: 0.20, blue: 0.20, alpha: 1) // dark gray
        case .bike_lane:            return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1) // near-black
        case .bus_bike_lane:        return .init(red: 0.25, green: 0.25, blue: 0.25, alpha: 1) // dark gray
        case .shared_lane:          return .init(red: 0.20, green: 0.20, blue: 0.20, alpha: 1) // dark
        case .signed_route:         return .init(red: 0.35, green: 0.35, blue: 0.35, alpha: 1) // medium gray
        case .unpaved_trail:        return .init(red: 0.55, green: 0.35, blue: 0.17, alpha: 1) // brown
        case .mountain_bike_trail:  return .init(red: 0.55, green: 0.17, blue: 0.75, alpha: 1) // purple
        }
    }

    var color: Color { Color(uiColor) }

    var lineWidth: CGFloat {
        switch self {
        case .protected_lane, .off_street_trail: return 5
        case .bike_lane, .bus_bike_lane, .contraflow_lane: return 4
        case .shared_lane, .unpaved_trail, .mountain_bike_trail: return 3
        case .signed_route: return 2
        }
    }

    /// Dash patterns approximating the legend's line styles.
    var dashPattern: [NSNumber]? {
        switch self {
        case .off_street_trail:     return nil          // solid (double-line styling not supported natively)
        case .protected_lane:       return nil          // solid
        case .contraflow_lane:      return [2, 3]       // tight ticks
        case .bike_lane:            return nil          // solid
        case .bus_bike_lane:        return [6, 3, 2, 3] // dot-rect
        case .shared_lane:          return [10, 6]      // sharrow dashes
        case .signed_route:         return [2, 4]       // small dots
        case .unpaved_trail:        return [8, 4]       // mid dashes
        case .mountain_bike_trail:  return [6, 4]       // shorter dashes
        }
    }

    var label: String {
        switch self {
        case .off_street_trail:     return String(localized: "Off-Street Trail")
        case .protected_lane:       return String(localized: "Protected Bike Lane")
        case .contraflow_lane:      return String(localized: "Contraflow Lane")
        case .bike_lane:            return String(localized: "Bike Lane")
        case .bus_bike_lane:        return String(localized: "Bus/Bike Lane")
        case .shared_lane:          return String(localized: "Shared Lane (Sharrow)")
        case .signed_route:         return String(localized: "On-Street Signed Route")
        case .unpaved_trail:        return String(localized: "Unpaved Trail")
        case .mountain_bike_trail:  return String(localized: "Mountain Bike Trail")
        }
    }
}

// MARK: - Infrastructure Feature

struct BikeInfraFeature {
    let name: String
    let type: InfraType
    let coordinates: [CLLocationCoordinate2D]
    let extensionKm: String?
    let reason: String?
    let status: String?
    let forecast: String?
}

// MARK: - POI Type

/// DC Bike Map amenities + user reports, mirroring the legend.
/// Order here drives the legend / Layers panel display order.
enum POIType: String, CaseIterable, Codable {
    // Featured (top of list)
    case secure_parking        // Secure Bike Parking
    case capital_bikeshare     // Capital Bikeshare station
    case fixit_stand           // self-service repair stand (includes air pump)
    case bike_shop             // Bike Sales & Repairs

    // User reports
    case furto                 // Bike Theft
    case acidente_ferido       // Cyclist Injury
    case acidente_morte        // Cyclist Fatality

    // Remaining amenities
    case trail_access          // Trail Access Point
    case water_fill            // Water Fill Stations
    case restroom              // Public Restrooms
    case metrorail             // Metrorail Station
    case commuter_rail         // MARC / VRE / Amtrak
    case rec_center            // DC Recreation Center
    case landmark              // Landmark

    var emoji: String {
        switch self {
        case .trail_access:        return "🟢"
        case .capital_bikeshare:   return "🚴"
        case .fixit_stand:         return "🔧"
        case .bike_shop:           return "🏪"
        case .secure_parking:      return "🚲"
        case .water_fill:          return "💧"
        case .restroom:            return "🚻"
        case .metrorail:           return "Ⓜ️"
        case .commuter_rail:       return "🚆"
        case .rec_center:          return "🏀"
        case .landmark:            return "🏛"
        case .furto:               return "🔓"
        case .acidente_ferido:     return "⚠️"
        case .acidente_morte:      return "❌"
        }
    }

    var label: String {
        switch self {
        case .trail_access:        return String(localized: "Trail Access Point")
        case .capital_bikeshare:   return String(localized: "Capital Bikeshare")
        case .fixit_stand:         return String(localized: "Fix-it Stand")
        case .bike_shop:           return String(localized: "Bike Sales & Repairs")
        case .secure_parking:      return String(localized: "Bike Parking")
        case .water_fill:          return String(localized: "Water Fill Stations")
        case .restroom:            return String(localized: "Public Restrooms")
        case .metrorail:           return String(localized: "Metro")
        case .commuter_rail:       return String(localized: "Commuter Rail Station")
        case .rec_center:          return String(localized: "DC Recreation Center")
        case .landmark:            return String(localized: "Landmark")
        case .furto:               return String(localized: "Bike Thefts")
        case .acidente_ferido:     return String(localized: "Cyclist Accidents")
        case .acidente_morte:      return String(localized: "Fatal Accidents")
        }
    }

    var uiColor: UIColor {
        switch self {
        case .trail_access:        return .init(red: 0.12, green: 0.55, blue: 0.20, alpha: 1) // dark green
        case .capital_bikeshare:   return .init(red: 0.86, green: 0.15, blue: 0.15, alpha: 1) // red (Capital Bikeshare brand)
        case .fixit_stand:         return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1) // black
        case .bike_shop:           return .init(red: 0.85, green: 0.47, blue: 0.04, alpha: 1) // orange
        case .secure_parking:      return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1) // black (lock)
        case .water_fill:          return .init(red: 0.03, green: 0.57, blue: 0.70, alpha: 1) // teal
        case .restroom:            return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1) // black
        case .metrorail:           return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1) // black (Metro 'M')
        case .commuter_rail:       return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        case .rec_center:          return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        case .landmark:            return .init(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)
        case .furto:               return .init(red: 0.29, green: 0.34, blue: 0.41, alpha: 1)
        case .acidente_ferido:     return .init(red: 0.92, green: 0.70, blue: 0.00, alpha: 1)
        case .acidente_morte:      return .init(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
        }
    }

    var color: Color { Color(uiColor) }

    /// Whether end users can add a POI of this type.
    /// Admin-only types (transit, rec center, landmark) come from imports.
    var canContribute: Bool {
        switch self {
        case .capital_bikeshare, .fixit_stand, .bike_shop,
             .secure_parking, .water_fill, .restroom, .trail_access,
             .furto, .acidente_ferido:
            return true
        case .metrorail, .commuter_rail, .rec_center, .landmark, .acidente_morte:
            return false
        }
    }
}

// MARK: - POI

struct POI: Identifiable, Codable, Equatable {
    var id: String
    var type: String
    var lat: Double
    var lng: Double
    var title: String
    var description: String
    var author: String
    var createdAt: Date?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var poiType: POIType { POIType(rawValue: type) ?? .secure_parking }
}


enum MapPickingMode {
    case addPoint
}

// MARK: - Custom MKPolyline

final class BikePolyline: MKPolyline {
    var infraType: InfraType = .bike_lane
    var featureName: String = ""
    var extensionKm: String?
    var reason: String?
    var status: String?
    var forecast: String?
}

// MARK: - POI Annotation

final class POIAnnotation: MKPointAnnotation {
    let poi: POI
    init(poi: POI) {
        self.poi = poi
        super.init()
        coordinate = poi.coordinate
        title = poi.title
    }
}

// MARK: - Avatar mapping

// MARK: - Avatar View

struct AvatarView: View {
    let id: String
    var size: CGFloat = 40

    var body: some View {
        Image(id)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 1))
    }
}

// DC fauna avatars — Washington, D.C. native / urban wildlife,
// listed alphabetically by display name.
let avatarList: [(id: String, name: String)] = [
    ("bobcat",   "Bobcat"),
    ("cardinal", "Cardinal"),
    ("crow",     "Crow"),
    ("eagle",    "Eagle"),
    ("fox",      "Fox"),
    ("otter",    "Otter"),
    ("owl",      "Owl"),
    ("raccoon",  "Raccoon"),
    ("skunk",    "Skunk"),
    ("squirrel", "Squirrel")
]
