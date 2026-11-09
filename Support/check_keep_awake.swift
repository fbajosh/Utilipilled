import Foundation

@main
enum KeepAwakeChecks {
    static func main() throws {
        let suite = "local.Utilipilled.duration-test.\(UUID().uuidString)"
        let prefs = UserDefaults(suiteName: suite)!
        defer { prefs.removePersistentDomain(forName: suite) }
        let module = KeepAwakeModule(defaults: prefs)
        try module.setDuration(.halfHour)
        precondition(!module.isEnabled, "Selecting a duration must not start Keep Awake")
        assert(!module.isEnabled)
        try module.setDuration(.halfHour)
        try module.setEnabled(true)
        let first = prefs.object(forKey: "keepAwake.deadline") as! Date
        assert(first.timeIntervalSinceNow > 1790)
        try module.setDuration(.twelveHours)
        assert((prefs.object(forKey: "keepAwake.deadline") as! Date).timeIntervalSinceNow > 43190)
        module.suspend()
        let resumed = KeepAwakeModule(defaults: prefs)
        try resumed.resume(); assert(resumed.isEnabled)
        try resumed.setDuration(.untilRestart)
        assert(prefs.object(forKey: "keepAwake.deadline") == nil)
        resumed.suspend()
        let sameBoot = KeepAwakeModule(defaults: prefs)
        try sameBoot.resume(); assert(sameBoot.isEnabled)
        sameBoot.suspend()
        prefs.set("previous-boot", forKey: "keepAwake.boot")
        let nextBoot = KeepAwakeModule(defaults: prefs)
        try nextBoot.resume(); assert(!nextBoot.isEnabled && !prefs.bool(forKey: "keepAwake.active"))
        try nextBoot.setDuration(.indefinitely); try nextBoot.setEnabled(true); nextBoot.suspend()
        prefs.set("previous-boot", forKey: "keepAwake.boot")
        let forever = KeepAwakeModule(defaults: prefs)
        try forever.resume(); assert(forever.isEnabled)
        try forever.setEnabled(false); assert(!prefs.bool(forKey: "keepAwake.active"))
        prefs.set(KeepAwakeModule.Duration.halfHour.rawValue, forKey: "keepAwake.duration")
        prefs.set(true, forKey: "keepAwake.active")
        prefs.set(Date().addingTimeInterval(0.25), forKey: "keepAwake.deadline")
        let expires = KeepAwakeModule(defaults: prefs)
        try expires.resume(); assert(expires.isEnabled)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        assert(!expires.isEnabled && !prefs.bool(forKey: "keepAwake.active"))
        print("Native duration, selection change, relaunch, boot boundary, indefinite, cancellation and expiry checks passed")
        prefs.set(true, forKey: "keepAwake.active")
        prefs.set(Date().addingTimeInterval(-1), forKey: "keepAwake.deadline")
        let expired = KeepAwakeModule(defaults: prefs)
        try expired.resume(); precondition(!expired.isEnabled)
    }
}
