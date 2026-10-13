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

/// What the Home call area shows for the selected area.
struct CallPlan: Equatable {
    static let visibleLimit = 5
    static let empty = CallPlan(groups: [], missingCore: [])

    /// Voice numbers for emergency dispatch, sorted for display.
    let groups: [NumberGroup]
    /// Police / fire / ambulance with no verified number and no all-emergencies number.
    let missingCore: [ServiceCategory]

    var isEmpty: Bool { groups.isEmpty }
    var isSingleNumber: Bool { groups.count == 1 }
    var visibleGroups: [NumberGroup] { Array(groups.prefix(Self.visibleLimit)) }
    var overflowGroups: [NumberGroup] { Array(groups.dropFirst(Self.visibleLimit)) }
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
