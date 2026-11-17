import Foundation

@main
enum PercentageHiderChecks {
    static func main() throws {
        typealias Policy = PercentageHiderPolicy
        typealias Setting = Policy.Setting
        let suite = "local.Utilipilled.percentage-test.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let module = PercentageHiderModule(defaults: prefs)
        precondition(!module.enabled && module.threshold == 90 && module.mode == .always && module.target == .percentage)
        for threshold in Policy.thresholds {
            for mode in Policy.Mode.allCases {
                for charging in [false, true] {
                    for level in [Double(threshold) - 0.01, Double(threshold), 100] {
                        let hide = level >= Double(threshold) && (mode == .always || charging)
                        precondition(Policy.shouldShow(level: level, charging: charging, threshold: threshold, mode: mode) == !hide)
                    }
                }
            }
        }
        var values: [Setting: Int] = [.battery: 2, .percentage: 1]
        var writes = 0
        var fail: Setting?
        func makeSession() -> PercentageHiderSession {
            PercentageHiderSession(defaults: prefs, read: { values[$0] }, write: { key, value in
                if key == fail { throw PercentageHiderSession.Failure("Simulated failure") }
                writes += 1; values[key] = value
            })
        }
        let session = makeSession()
        try session.update(target: .percentage, visible: false)
        precondition(values == [.battery: 2, .percentage: 0] && writes == 1)
        for _ in 0..<20 { try session.update(target: .percentage, visible: false) }
        let initiallyHiding = try session.isHiding()
        precondition(writes == 1 && initiallyHiding)
        try session.update(target: .battery, visible: false)
        precondition(values == [.battery: 8, .percentage: 1])
        try session.update(target: .both, visible: false)
        precondition(values == [.battery: 8, .percentage: 0])
        try makeSession().restore() // Relaunch/crash recovery uses the original saved settings.
        precondition(values == [.battery: 2, .percentage: 1])
        values = [:]
        try session.update(target: .both, visible: false)
        try session.restore()
        precondition(values.isEmpty) // Restore absent preference keys, too.
        values = [.battery: 2, .percentage: 1]
        fail = .percentage
        do { try session.update(target: .both, visible: false); preconditionFailure("Expected write failure") }
        catch { }
        let partiallyHiding = try session.isHiding()
        precondition(partiallyHiding) // Battery changed before the percentage write failed.
        fail = nil
        try session.restore()
        precondition(values == [.battery: 2, .percentage: 1])
        try session.update(target: .both, visible: false)
        fail = .battery
        do { try session.restore(); preconditionFailure("Expected restore failure") } catch { }
        precondition(values[.percentage] == 1 && values[.battery] == 8)
        fail = nil
        try makeSession().restore()
        precondition(values == [.battery: 2, .percentage: 1])
        print("Percentage Hider boundary, mode, target, deduplication, restoration and failure checks passed")
    }
}
