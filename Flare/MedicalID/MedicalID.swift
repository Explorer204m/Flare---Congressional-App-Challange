import Foundation

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum BloodType: String, Codable, CaseIterable, Identifiable {
    case aPositive = "A+", aNegative = "A-"
    case bPositive = "B+", bNegative = "B-"
    case abPositive = "AB+", abNegative = "AB-"
    case oPositive = "O+", oNegative = "O-"

    var id: String { rawValue }
}

enum OrganDonation: String, Codable, CaseIterable, Identifiable {
    case unspecified, yes, no

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unspecified: return "Not stated"
        case .yes: return "Yes"
        case .no: return "No"
        }
    }
}

struct EmergencyContactPerson: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var relationship = ""
    var phone = ""

    init() {}

    // Tolerant decoding: a field added in a later version must never make an older
    // saved Medical ID unreadable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        relationship = try c.decodeIfPresent(String.self, forKey: .relationship) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
    }

    var isBlank: Bool {
        name.trimmed.isEmpty && relationship.trimmed.isEmpty && phone.trimmed.isEmpty
    }

    /// A phone value that is non-empty but can't be dialed safely.
    var hasInvalidPhone: Bool {
        !phone.trimmed.isEmpty && Dialer.normalized(phone) == nil
    }

    var displayName: String {
        name.trimmed.isEmpty ? "Unnamed contact" : name.trimmed
    }
}

/// Everything the person chose to put in their Medical ID. All of it is optional.
struct MedicalID: Codable, Equatable {
    static let maxContacts = 5

    var fullName = ""
    var dateOfBirth: Date?
    var bloodType: BloodType?
    var allergies = ""
    var conditions = ""
    var medications = ""
    var notes = ""
    var organDonation: OrganDonation = .unspecified
    var contacts: [EmergencyContactPerson] = []
    var updatedAt: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName) ?? ""
        dateOfBirth = try c.decodeIfPresent(Date.self, forKey: .dateOfBirth)
        bloodType = try c.decodeIfPresent(BloodType.self, forKey: .bloodType)
        allergies = try c.decodeIfPresent(String.self, forKey: .allergies) ?? ""
        conditions = try c.decodeIfPresent(String.self, forKey: .conditions) ?? ""
        medications = try c.decodeIfPresent(String.self, forKey: .medications) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        organDonation = try c.decodeIfPresent(OrganDonation.self, forKey: .organDonation) ?? .unspecified
        contacts = try c.decodeIfPresent([EmergencyContactPerson].self, forKey: .contacts) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    /// True when nothing has been filled in.
    var isEmpty: Bool {
        fullName.trimmed.isEmpty && dateOfBirth == nil && bloodType == nil
            && allergies.trimmed.isEmpty && conditions.trimmed.isEmpty
            && medications.trimmed.isEmpty && notes.trimmed.isEmpty
            && organDonation == .unspecified && contacts.allSatisfy { $0.isBlank }
    }

    var hasInvalidPhone: Bool { contacts.contains { $0.hasInvalidPhone } }

    /// Whole years since the date of birth, or nil.
    var age: Int? {
        guard let dateOfBirth else { return nil }
        let years = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year
        guard let years, years >= 0 else { return nil }
        return years
    }

    /// Trimmed copy with blank contacts dropped, ready to save.
    func cleaned() -> MedicalID {
        var copy = self
        copy.fullName = fullName.trimmed
        copy.allergies = allergies.trimmed
        copy.conditions = conditions.trimmed
        copy.medications = medications.trimmed
        copy.notes = notes.trimmed
        copy.contacts = contacts.filter { !$0.isBlank }.map { contact in
            var c = contact
            c.name = contact.name.trimmed
            c.relationship = contact.relationship.trimmed
            c.phone = contact.phone.trimmed
            return c
        }
        return copy
    }
}
