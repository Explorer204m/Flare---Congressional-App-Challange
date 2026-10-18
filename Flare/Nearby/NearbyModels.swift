import SwiftUI
import MapKit
import CoreLocation

/// The kinds of place the Nearby tab looks for.
enum NearbyKind: String, CaseIterable, Identifiable, Codable {
    case hospital, police, fire, pharmacy
    /// For pets. Kept out of "Nearest" and the Home tiles, which are for people.
    case vet

    var id: String { rawValue }

    var isForPeople: Bool { self != .vet }

    static var peopleKinds: [NearbyKind] { allCases.filter { $0.isForPeople } }

    var title: String {
        switch self {
        case .hospital: return "Hospital"
        case .police: return "Police"
        case .fire: return "Fire station"
        case .pharmacy: return "Pharmacy"
        case .vet: return "Emergency vet"
        }
    }

    /// Heading above the list of results.
    var listTitle: String {
        switch self {
        case .hospital: return "Hospitals near you"
        case .police: return "Police near you"
        case .fire: return "Fire stations near you"
        case .pharmacy: return "Pharmacies near you"
        case .vet: return "Emergency vets near you"
        }
    }

    var systemImage: String {
        switch self {
        case .hospital: return "cross.case.fill"
        case .police: return "shield.fill"
        case .fire: return "flame.fill"
        case .pharmacy: return "pills.fill"
        case .vet: return "pawprint.fill"
        }
    }

    var tint: Color {
        switch self {
        case .hospital: return FlareColor.hospital
        case .police: return FlareColor.police
        case .fire: return FlareColor.fire
        case .pharmacy: return FlareColor.pharmacy
        case .vet: return FlareColor.vet
        }
    }

    /// The Apple Maps category searched for. Vets have none that works on every supported
    /// iOS version, so they are found with a text search instead.
    var category: MKPointOfInterestCategory? {
        switch self {
        case .hospital: return .hospital
        case .police: return .police
        case .fire: return .fireStation
        case .pharmacy: return .pharmacy
        case .vet: return nil
        }
    }
}

/// What the Map tab is showing: the nearest place of each kind, or one kind of place.
enum NearbyScope: Hashable, Identifiable {
    /// The nearest hospital, police station, fire station and pharmacy: one of each.
    case nearestOfEach
    case kind(NearbyKind)

    static let all: [NearbyScope] = [.nearestOfEach] + NearbyKind.allCases.map { NearbyScope.kind($0) }

    var id: String {
        switch self {
        case .nearestOfEach: return "nearest"
        case .kind(let kind): return kind.rawValue
        }
    }

    var title: String {
        switch self {
        case .nearestOfEach: return "Nearest"
        case .kind(let kind): return kind.title
        }
    }

    /// Heading above the list of results.
    var listTitle: String {
        switch self {
        case .nearestOfEach: return "Nearest of each"
        case .kind(let kind): return kind.listTitle
        }
    }

    /// For sentences such as "No saved places near here".
    var noun: String {
        switch self {
        case .nearestOfEach: return "places"
        case .kind(let kind): return kind.title.lowercased()
        }
    }

    var systemImage: String {
        switch self {
        case .nearestOfEach: return "mappin.and.ellipse"
        case .kind(let kind): return kind.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .nearestOfEach: return FlareColor.link
        case .kind(let kind): return kind.tint
        }
    }
}

/// One place found by Apple Maps, kept so it can be shown again without a connection.
struct NearbyPlace: Codable, Identifiable, Hashable {
    let id: String
    let kind: NearbyKind
    let name: String
    let latitude: Double
    let longitude: Double
    let phone: String?
    let address: String?
    /// When this place was last returned by a live search.
    let savedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    func distance(from other: CLLocation) -> CLLocationDistance {
        location.distance(from: other)
    }

    init?(item: MKMapItem, kind: NearbyKind, savedAt: Date) {
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return nil }

        let rawName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        let addressParts = [street, placemark.locality ?? ""].filter { !$0.isEmpty }
        let phone = item.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

        self.id = "\(kind.rawValue):\(Int((coordinate.latitude * 10_000).rounded())):\(Int((coordinate.longitude * 10_000).rounded()))"
        self.kind = kind
        self.name = rawName.isEmpty ? kind.title : rawName
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.phone = (phone?.isEmpty ?? true) ? nil : phone
        self.address = addressParts.isEmpty ? nil : addressParts.joined(separator: ", ")
        self.savedAt = savedAt
    }
}

// MARK: - Geometry helpers

enum Geo {
    /// Initial great-circle bearing from `a` to `b`, in degrees clockwise from true north (0..<360).
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return normalized(degrees)
    }

    /// Wraps any angle into 0..<360.
    static func normalized(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Plain-language direction for a bearing, for example "north-east".
    static func cardinal(_ degrees: Double) -> String {
        let names = ["north", "north-east", "east", "south-east",
                     "south", "south-west", "west", "north-west"]
        let index = Int((normalized(degrees) + 22.5) / 45) % 8
        return names[index]
    }

    private static let formatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    /// Distance in the person's own units (km or miles).
    static func distanceText(_ meters: CLLocationDistance) -> String {
        formatter.string(fromDistance: meters)
    }
}
