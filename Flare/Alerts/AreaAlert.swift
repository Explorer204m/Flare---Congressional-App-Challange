import Foundation
import CoreLocation

/// How serious an alert is, using the CAP scale the US National Weather Service uses.
enum AlertSeverity: Int, Codable, Comparable {
    case unknown = 0, minor, moderate, severe, extreme

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    init(cap: String?) {
        switch cap?.lowercased() {
        case "extreme": self = .extreme
        case "severe": self = .severe
        case "moderate": self = .moderate
        case "minor": self = .minor
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .extreme: return "Extreme"
        case .severe: return "Severe"
        case .moderate: return "Moderate"
        case .minor: return "Minor"
        case .unknown: return "Severity not given"
        }
    }
}

/// One official warning for the person's area, as issued. Flare never writes or changes the text.
struct AreaAlert: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        /// US National Weather Service (api.weather.gov): local weather and flood warnings, US only.
        case nws
        /// Global Disaster Alert and Coordination System: major disasters worldwide.
        case gdacs
    }

    let id: String
    let source: Source
    /// For example "Flood Warning" or "Earthquake in Indonesia".
    let event: String
    let headline: String?
    let details: String?
    let instruction: String?
    /// The agency that issued it.
    let sender: String
    let area: String?
    let severity: AlertSeverity
    let effective: Date?
    let expires: Date?
    let link: URL?

    func isExpired(at now: Date) -> Bool {
        guard let expires else { return false }
        return expires <= now
    }

    /// Updates of the same warning get new ids; this keeps them to one notification.
    var notifyKey: String { "\(source.rawValue)|\(event)|\(area ?? "")" }
}

// MARK: - Parsing

/// Turns the two feeds into `AreaAlert`s. Pure functions, no networking, so they can be tested.
enum AreaAlertParser {
    /// Skips entries it can't read instead of failing the whole list.
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// Date formatters for one parse of one feed: built once per feed instead of once per
    /// timestamp. Each parse makes its own, so background parsing never shares a formatter
    /// between threads. Same rules as before: plain internet date-time first, then with
    /// fractional seconds; GDACS dates are UTC without a zone, with ISO as the fallback.
    private final class DateParser {
        private let plain = ISO8601DateFormatter()
        private lazy var fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()
        private lazy var gdacsFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter
        }()

        func iso(_ text: String?) -> Date? {
            guard let text else { return nil }
            return plain.date(from: text) ?? fractional.date(from: text)
        }

        func gdacs(_ text: String?) -> Date? {
            guard let text else { return nil }
            return gdacsFormatter.date(from: text) ?? iso(text)
        }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    // MARK: National Weather Service

    private struct NWSCollection: Decodable {
        let features: [Lossy<Feature>]
        struct Feature: Decodable {
            let id: String?
            let properties: Properties
        }
        struct Properties: Decodable {
            let id: String?
            let event: String?
            let headline: String?
            let description: String?
            let instruction: String?
            let severity: String?
            let effective: String?
            let onset: String?
            let expires: String?
            let ends: String?
            let senderName: String?
            let areaDesc: String?
            let status: String?
            let messageType: String?
        }
    }

    /// Active alerts for one point. Only real alerts ("Actual"), never tests, exercises or cancellations.
    static func nws(_ data: Data, now: Date = Date()) throws -> [AreaAlert] {
        let collection = try JSONDecoder().decode(NWSCollection.self, from: data)
        let dates = DateParser()
        return collection.features.compactMap { $0.value }.compactMap { feature -> AreaAlert? in
            let p = feature.properties
            guard (p.status ?? "Actual") == "Actual",
                  (p.messageType ?? "Alert") != "Cancel",
                  let event = trimmed(p.event),
                  let id = p.id ?? feature.id else { return nil }
            let alert = AreaAlert(
                id: id,
                source: .nws,
                event: event,
                headline: trimmed(p.headline),
                details: trimmed(p.description),
                instruction: trimmed(p.instruction),
                sender: trimmed(p.senderName) ?? "National Weather Service",
                area: trimmed(p.areaDesc),
                severity: AlertSeverity(cap: p.severity),
                effective: dates.iso(p.onset) ?? dates.iso(p.effective),
                expires: dates.iso(p.ends) ?? dates.iso(p.expires),
                link: nil)
            return alert.isExpired(at: now) ? nil : alert
        }
    }

    // MARK: GDACS

    private struct GDACSCollection: Decodable {
        let features: [Lossy<Feature>]
        struct Feature: Decodable {
            let bbox: [Double]?
            let geometry: Geometry?
            let properties: Properties
        }
        struct Geometry: Decodable {
            let coordinates: [Double]?
            enum CodingKeys: String, CodingKey { case coordinates }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // Points only; other shapes have nested arrays and are left to the bounding box.
                coordinates = try? container.decode([Double].self, forKey: .coordinates)
            }
        }
        struct Properties: Decodable {
            let eventtype: String?
            let eventid: Flexible?
            let episodeid: Flexible?
            let name: String?
            let description: String?
            let htmldescription: String?
            let alertlevel: String?
            let iscurrent: String?
            let fromdate: String?
            let country: String?
            let url: Links?
            let severitydata: SeverityData?
        }
        struct Links: Decodable { let report: String? }
        struct SeverityData: Decodable { let severitytext: String? }
        /// GDACS sends ids as numbers; accept text too.
        struct Flexible: Decodable {
            let text: String
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Int.self) {
                    text = String(number)
                } else {
                    text = try container.decode(String.self)
                }
            }
        }
    }

    static let gdacsRadius: CLLocationDistance = 300_000

    private static func eventKind(_ code: String?) -> String {
        switch code?.uppercased() {
        case "EQ": return "Earthquake"
        case "TC": return "Tropical cyclone"
        case "FL": return "Flood"
        case "VO": return "Volcano"
        case "DR": return "Drought"
        case "WF": return "Wildfire"
        case "TS": return "Tsunami"
        default: return "Disaster"
        }
    }

    /// Current orange and red GDACS events that cover or are near the person
    /// (inside the event's bounding box, or within 300 km of its centre).
    static func gdacs(_ data: Data, near location: CLLocation, now: Date = Date()) throws -> [AreaAlert] {
        let collection = try JSONDecoder().decode(GDACSCollection.self, from: data)
        let dates = DateParser()
        return collection.features.compactMap { $0.value }.compactMap { feature -> AreaAlert? in
            let p = feature.properties
            let level = (p.alertlevel ?? "").lowercased()
            guard level == "orange" || level == "red",
                  (p.iscurrent ?? "true").lowercased() == "true",
                  let eventID = p.eventid?.text else { return nil }

            var near = false
            if let c = feature.geometry?.coordinates, c.count >= 2 {
                let centre = CLLocation(latitude: c[1], longitude: c[0])
                near = centre.distance(from: location) <= gdacsRadius
            }
            if !near, let box = feature.bbox, box.count == 4 {
                let lat = location.coordinate.latitude, lon = location.coordinate.longitude
                let margin = 0.5
                near = lon >= box[0] - margin && lon <= box[2] + margin
                    && lat >= box[1] - margin && lat <= box[3] + margin
            }
            guard near else { return nil }

            let kind = eventKind(p.eventtype)
            var details: [String] = []
            if let text = trimmed(p.htmldescription) ?? trimmed(p.description) { details.append(text) }
            if let text = trimmed(p.severitydata?.severitytext) { details.append(text) }

            return AreaAlert(
                id: "gdacs-\(p.eventtype ?? "X")-\(eventID)-\(p.episodeid?.text ?? "0")",
                source: .gdacs,
                event: trimmed(p.name) ?? kind,
                headline: "\(level == "red" ? "Red" : "Orange") alert: \(kind.lowercased())\(p.country.map { " in \($0)" } ?? "")",
                details: details.isEmpty ? nil : details.joined(separator: "\n"),
                instruction: nil,
                sender: "GDACS (Global Disaster Alert and Coordination System)",
                area: trimmed(p.country),
                severity: level == "red" ? .extreme : .severe,
                effective: dates.gdacs(p.fromdate),
                expires: nil,
                link: p.url?.report.flatMap { URL(string: $0) })
        }
    }
}
