import Foundation

// Process identity is necessary for running instances; exclusions use bundle identity only.
struct ApplicationHistory {
    private(set) var order: [Int32] = []

    mutating func synchronize(_ running: [Int32], frontmost: Int32?) {
        let live = Set(running)
        order.removeAll { !live.contains($0) }
        for pid in running where !order.contains(pid) { order.append(pid) }
        if let frontmost, live.contains(frontmost) { activate(frontmost) }
    }

    mutating func activate(_ pid: Int32) {
        order.removeAll { $0 == pid }; order.insert(pid, at: 0)
    }
}

// A session freezes MRU order until dismissal. Activations never reorder visible tiles.
struct SwitcherSession {
    private(set) var applications: [Int32] = []
    private(set) var selected: Int32?
    private(set) var hasRevealedHiddenApplications = false
    private var hiddenApplications: [Int32] = []
    private var showAfter: HiddenAppReveal = .never
    private var cycleLength = 0
    private var cycleOffset = 0
    private var completedCycles = 0
    private var revealOnNextAdvance = false
    var isActive: Bool { !applications.isEmpty }

    mutating func begin(_ applications: [Int32], frontmost: Int32?, backward: Bool,
                        hidden: [Int32] = [], showAfter: HiddenAppReveal = .never) {
        end()
        self.applications = applications
        var seen = Set(applications)
        hiddenApplications = hidden.filter { seen.insert($0).inserted }
        self.showAfter = showAfter
        // With no visible apps there is no cycle to traverse. Allow configured
        // reveal as an escape hatch; Never continues to show no excluded apps.
        if applications.isEmpty && showAfter != .never && !hiddenApplications.isEmpty {
            self.applications = hiddenApplications
            hiddenApplications = []
            hasRevealedHiddenApplications = true
        }
        let applications = self.applications
        guard !applications.isEmpty else { selected = nil; return }
        cycleLength = applications.count
        if let frontmost, let index = applications.firstIndex(of: frontmost) {
            selected = applications[(index + (backward ? applications.count - 1 : 1)) % applications.count]
            cycleOffset = backward ? -1 : 1
        } else {
            selected = applications.first
        }
        revealIfNeeded(backward: backward)
    }

    mutating func move(_ delta: Int) {
        guard delta != 0 else { return }
        // Each crossed item counts once, including keyboard repeats. Reversing
        // direction undoes partial progress; completed laps still count.
        for _ in 0..<abs(delta) {
            guard let selected, let index = applications.firstIndex(of: selected) else { return }
            let direction = delta > 0 ? 1 : -1
            if revealOnNextAdvance {
                revealHidden(backward: direction < 0)
                continue
            }
            let count = applications.count
            self.selected = applications[(index + direction + count) % count]
            if !hasRevealedHiddenApplications && showAfter != .never {
                cycleOffset += direction
                revealIfNeeded(backward: direction < 0)
            }
        }
    }

    mutating func select(_ pid: Int32) {
        if applications.contains(pid), selected != pid {
            selected = pid; cycleOffset = 0; revealOnNextAdvance = false
        }
    }

    mutating func retain(_ eligible: Set<Int32>, hiddenEligible: Set<Int32>? = nil) {
        let index = selected.flatMap { applications.firstIndex(of: $0) } ?? 0
        let previousCount = applications.count
        applications.removeAll { !eligible.contains($0) }
        hiddenApplications.removeAll { !(hiddenEligible ?? eligible).contains($0) }
        if hiddenApplications.isEmpty { revealOnNextAdvance = false }
        if applications.count != previousCount {
            cycleLength = applications.count; cycleOffset = 0; revealOnNextAdvance = false
        }
        if applications.isEmpty && !hiddenApplications.isEmpty && showAfter != .never {
            revealHidden(backward: false)
        }
        if let selected, applications.contains(selected) { return }
        selected = applications.isEmpty ? nil : applications[min(index, applications.count - 1)]
    }

    private mutating func revealIfNeeded(backward: Bool) {
        guard showAfter != .never, !hiddenApplications.isEmpty, cycleLength > 0,
              abs(cycleOffset) >= cycleLength else { return }
        completedCycles += 1
        cycleOffset = 0
        if completedCycles >= showAfter.completedCyclesBeforeReveal {
            if showAfter == .startOfSecondCycle { revealOnNextAdvance = true }
            else { revealHidden(backward: backward) }
        }
    }

    private mutating func revealHidden(backward: Bool) {
        revealOnNextAdvance = false
        guard !hiddenApplications.isEmpty else { return }
        // Keep existing icons in place and append the hidden apps in frozen MRU
        // order. Enter the revealed group immediately in the cycling direction.
        selected = backward ? hiddenApplications.last : hiddenApplications.first
        applications.append(contentsOf: hiddenApplications)
        hiddenApplications = []
        hasRevealedHiddenApplications = true
    }

    mutating func end() {
        applications = []; selected = nil; hiddenApplications = []
        hasRevealedHiddenApplications = false; showAfter = .never
        cycleLength = 0; cycleOffset = 0; completedCycles = 0; revealOnNextAdvance = false
    }
}
