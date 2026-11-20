import Foundation

enum HiddenAppReveal: Int, CaseIterable {
    // Preserve existing raw values; the additional timing gets a new value.
    case always = 4, endOfFirstCycle = 1, startOfSecondCycle = 3, endOfSecondCycle = 2, never = 0

    var title: String {
        switch self {
        case .always: return "Always"
        case .endOfFirstCycle: return "At end of first cycle"
        case .startOfSecondCycle: return "After start of second cycle"
        case .endOfSecondCycle: return "At end of second cycle"
        case .never: return "Never"
        }
    }

    var completedCyclesBeforeReveal: Int {
        switch self {
        case .always: return 0
        case .endOfSecondCycle: return 2
        default: return 1
        }
    }
}

struct ExcludedApplication: Codable, Equatable {
    let bundleIdentifier: String
    var displayName: String
    var applicationURL: URL?
}

final class ExclusionStore {
    private let defaults: UserDefaults
    private(set) var records: [String: ExcludedApplication] = [:]
    var identifiers: Set<String> { Set(records.keys) }
    var showAfter: HiddenAppReveal {
        get { HiddenAppReveal(rawValue: defaults.integer(forKey: "switcherHider.showAfter")) ?? .never }
        set { defaults.set(newValue.rawValue, forKey: "switcherHider.showAfter") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "switcherHider.excludedApps"),
           let saved = try? JSONDecoder().decode([ExcludedApplication].self, from: data) {
            for record in saved where !record.bundleIdentifier.isEmpty {
                records[record.bundleIdentifier] = record
            }
        }
    }

    func toggle(_ application: ExcludedApplication) {
        if records.removeValue(forKey: application.bundleIdentifier) == nil {
            records[application.bundleIdentifier] = application
        }
        save()
    }

    func refresh(_ applications: [ExcludedApplication]) {
        var changed = false
        for application in applications where records[application.bundleIdentifier] != nil {
            if records[application.bundleIdentifier] != application {
                records[application.bundleIdentifier] = application; changed = true
            }
        }
        if changed { save() }
    }

    private func save() {
        let sorted = records.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
        if let data = try? JSONEncoder().encode(sorted) {
            defaults.set(data, forKey: "switcherHider.excludedApps")
        }
    }
}
