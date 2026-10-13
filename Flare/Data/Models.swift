import Foundation

// MARK: - Areas

enum AreaType: String, Hashable {
    case country, territory, region, district, city

    var label: String {
        switch self {
        case .country: return "Country"
        case .territory: return "Territory"
        case .region: return "Region"
        case .district: return "District"
        case .city: return "City"
        }
    }

    /// Countries and territories are the roots of the coverage hierarchy.
    var isRoot: Bool { self == .country || self == .territory }
}

struct Area: Identifiable, Hashable {
    let id: Int64
    let parentID: Int64?
    let name: String
    let type: AreaType
    let countryCode: String
}

// MARK: - Services and contacts

enum ServiceCategory: String, CaseIterable, Hashable {
    case generalEmergency = "general_emergency"
    case medical
    case police
    case fire
    case rescue
    case poison
    case crisis
    case other

    /// Categories that can be dialed from the Home call area.
    var isDispatch: Bool {
        switch self {
        case .generalEmergency, .medical, .police, .fire, .rescue: return true
        case .poison, .crisis, .other: return false
        }
    }

    var sectionTitle: String {
        switch self {
        case .generalEmergency: return "All emergencies"
        case .medical: return "Ambulance"
        case .police: return "Police"
        case .fire: return "Fire"
        case .rescue: return "Rescue"
        case .poison: return "Poison help"
        case .crisis: return "Crisis support"
        case .other: return "Other"
        }
    }

    /// Order used for lists of numbers.
    static let displayOrder: [ServiceCategory] = [
        .generalEmergency, .medical, .police, .fire, .rescue, .poison, .crisis, .other
    ]
}

enum ContactChannel: String, Hashable {
    case voice, sms, web

    var label: String {
        switch self {
        case .voice: return "Call"
        case .sms: return "Text"
        case .web: return "Web"
        }
    }
}

/// One active contact, joined with its service and the area it covers.
/// Mirrors the columns returned by `lookup.sql` in the database package.
struct ContactRow: Identifiable, Hashable {
    var id: Int64 { contactID }

    let serviceID: Int64
    let serviceName: String
    let category: ServiceCategory
    let serviceDescription: String?
    let coverageAreaID: Int64
    let coverageName: String
    let coverageType: AreaType
    let countryCode: String
    let contactID: Int64
    let channel: ContactChannel
    let value: String
    let notes: String?
    /// nil means unknown. Never present this as "24/7".
    let availability: String?
    /// UTC timestamp of the most recent confirmed verification (ISO 8601).
    let lastConfirmedAt: String?
}

// MARK: - Dataset metadata

struct DatasetInfo: Equatable {
    let version: String
    let publishedRaw: String
    let publishedAt: Date?

    init(metadata: [String: String]) {
        version = metadata["dataset_version"] ?? "unknown"
        publishedRaw = metadata["published_at"] ?? ""
        publishedAt = ISO8601DateFormatter().date(from: publishedRaw)
    }
}

// MARK: - Helpers

extension String {
    /// Source names are lower-case or inconsistently capitalised; make them presentable.
    var sentenceCased: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        return String(first).uppercased() + trimmed.dropFirst()
    }
}

enum DateText {
    static func shortDate(fromISO iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
