import Foundation

/// Colour family for a call button. Mapped to real colours in the design layer.
enum CallTint: Hashable {
    case allPurpose, ambulance, police, fire, rescue
}

/// One dialable number, with every service that uses it.
///
/// Some countries report the same number for several services (for example
/// 119 for both fire and ambulance) and several numbers for one service.
/// Grouping by number keeps both cases honest: the app never picks a
/// "primary" number the dataset does not identify.
struct NumberGroup: Identifiable, Hashable {
    let id: String
    let displayNumber: String
    let dialURL: URL?
    let categories: Set<ServiceCategory>
    let serviceNames: [String]
    let contacts: [ContactRow]

    var coversEverything: Bool { categories.contains(.generalEmergency) }

    var title: String {
        if coversEverything { return "All emergencies" }
        let names: [(ServiceCategory, String)] = [
            (.medical, "Ambulance"), (.police, "Police"), (.fire, "Fire"), (.rescue, "Rescue")
        ]
        let present = names.filter { categories.contains($0.0) }.map { $0.1 }
        return present.isEmpty ? "Emergency" : present.joined(separator: " \u{00B7} ")
    }

    /// The service's own name, only when exactly one name uses this number.
    var subtitle: String? {
        guard serviceNames.count == 1, let name = serviceNames.first else { return nil }
        let cleaned = name.sentenceCased
        return cleaned.caseInsensitiveCompare(title) == .orderedSame ? nil : cleaned
    }

    var tint: CallTint {
        if coversEverything || categories.count > 1 { return .allPurpose }
        switch categories.first {
        case .some(.medical): return .ambulance
        case .some(.police): return .police
        case .some(.fire): return .fire
        case .some(.rescue): return .rescue
        default: return .allPurpose
        }
    }

    /// Which unit the dataset says answers this number ("Gendarmerie", "Police rescue"), if it names one.
    var unitLabel: String? {
        var labels: [String] = []
        for name in serviceNames {
            let part: String
            if let range = name.range(of: " \u{2014} ") {
                part = String(name[range.upperBound...])
            } else {
                part = name
            }
            let cleaned = part.sentenceCased
            if !cleaned.isEmpty && !labels.contains(cleaned) { labels.append(cleaned) }
        }
        return labels.isEmpty ? nil : labels.joined(separator: " \u{00B7} ")
    }

    fileprivate var sortRank: Int {
        if coversEverything { return 0 }
        if categories.count > 1 { return 1 }
        switch categories.first {
        case .some(.medical): return 2
        case .some(.police): return 3
        case .some(.fire): return 4
        case .some(.rescue): return 5
        default: return 6
        }
    }
}

/// Police, fire or ambulance when the dataset lists more than one number for it.
///
/// The dataset does not say which of several numbers is the main one (they are often
/// different units: gendarmerie, mobile police, anti-terrorist police). Flare does not
/// guess: the service gets one button that opens the list, each number named by its unit.
struct ServiceSlot: Identifiable, Hashable {
    let category: ServiceCategory
    let groups: [NumberGroup]

    var id: String { category.rawValue }

    var title: String {
        switch category {
        case .police: return "Police"
        case .fire: return "Fire"
        case .medical: return "Ambulance"
        case .rescue: return "Rescue"
        default: return "Emergency"
        }
    }

    var tint: CallTint {
        switch category {
        case .police: return .police
        case .fire: return .fire
        case .medical: return .ambulance
        case .rescue: return .rescue
        default: return .allPurpose
        }
    }
}

/// How the call area is arranged: the numbers that matter first, one button per service.
struct CallLayout {
    enum Entry: Identifiable, Hashable {
        case number(NumberGroup)
        case choice(ServiceSlot)

        var id: String {
            switch self {
            case .number(let group): return "n-" + group.id
            case .choice(let slot): return "c-" + slot.id
            }
        }
    }

    /// Always visible: all-emergencies numbers, then ambulance, police, fire and rescue.
    let main: [Entry]
    /// Other numbers (rescue and so on) shown under the main ones when there is room.
    let inline: [NumberGroup]
    /// Other numbers that go behind "Show more numbers".
    let overflow: [NumberGroup]

    var hasChoice: Bool {
        main.contains { if case .choice = $0 { return true } else { return false } }
    }
}

/// What Home's call area shows for the selected area.
struct CallPlan: Equatable {
    static let visibleLimit = 5
    static let empty = CallPlan(groups: [], missingCore: [])

    /// Voice numbers for emergency dispatch, sorted for display.
    let groups: [NumberGroup]
    /// Police / fire / ambulance with no verified number and no all-emergencies number.
    let missingCore: [ServiceCategory]

    var isEmpty: Bool { groups.isEmpty }
    var isSingleNumber: Bool { groups.count == 1 }

    /// One button per service. A service with exactly one number is one tap; a service with
    /// several becomes a single "choose" button, so a country with five police numbers
    /// still shows ambulance, police and fire at a glance.
    var layout: CallLayout {
        var main: [CallLayout.Entry] = []
        var placed = Set<String>()

        for group in groups where group.coversEverything {
            main.append(.number(group))
            placed.insert(group.id)
        }

        for category in [ServiceCategory.medical, .police, .fire, .rescue] {
            let candidates = groups.filter { !$0.coversEverything && $0.categories.contains(category) }
            if candidates.isEmpty { continue }
            if candidates.count == 1, let only = candidates.first {
                if placed.contains(only.id) { continue }   // already shown, e.g. one number for fire and ambulance
                main.append(.number(only))
                placed.insert(only.id)
            } else {
                main.append(.choice(ServiceSlot(category: category, groups: candidates)))
                placed.formUnion(candidates.map { $0.id })
            }
        }

        let rest = groups.filter { !placed.contains($0.id) }
        let fits = main.count + rest.count <= Self.visibleLimit
        return CallLayout(main: main,
                          inline: fits ? rest : [],
                          overflow: fits ? [] : rest)
    }
}

enum CallPlanner {
    /// Builds the call plan from the rows returned by the database lookup
    /// (selected area plus all of its ancestors). Pure function: no I/O.
    static func plan(from rows: [ContactRow]) -> CallPlan {
        let dispatchRows = rows.filter { $0.channel == .voice && $0.category.isDispatch }

        var order: [String] = []
        var buckets: [String: [ContactRow]] = [:]
        for row in dispatchRows {
            let key = Dialer.groupingKey(for: row.value)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(row)
        }

        var groups: [NumberGroup] = []
        for key in order {
            guard let members = buckets[key], let first = members.first else { continue }
            var names: [String] = []
            for member in members where !names.contains(member.serviceName) {
                names.append(member.serviceName)
            }
            groups.append(NumberGroup(
                id: key,
                displayNumber: first.value,
                dialURL: Dialer.telURL(for: first.value),
                categories: Set(members.map { $0.category }),
                serviceNames: names,
                contacts: members
            ))
        }

        groups.sort { lhs, rhs in
            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
            return lhs.displayNumber.localizedStandardCompare(rhs.displayNumber) == .orderedAscending
        }

        var covered = Set<ServiceCategory>()
        for group in groups { covered.formUnion(group.categories) }
        var missing: [ServiceCategory] = []
        if !covered.contains(.generalEmergency) {
            missing = [ServiceCategory.police, .fire, .medical].filter { !covered.contains($0) }
        }
        return CallPlan(groups: groups, missingCore: missing)
    }
}
