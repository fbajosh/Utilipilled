import Foundation
import IOKit.ps

struct PercentageHiderPolicy {
    enum Mode: String, CaseIterable { case whenCharging = "When charging", always = "Always" }
    enum Target: String, CaseIterable {
        case battery = "Battery", percentage = "Percentage", both = "Both"
        var settings: [Setting] {
            switch self {
            case .battery: return [.battery]
            case .percentage: return [.percentage]
            case .both: return Setting.allCases
            }
        }
    }
    enum Setting: String, CaseIterable {
        case battery, percentage
        var key: String { self == .battery ? "Battery" : "BatteryShowPercentage" }
        func visible(_ value: Int?) -> Bool { self == .battery ? (value ?? 2) != 8 : (value ?? 0) == 1 }
        func value(visible: Bool) -> Int { self == .battery ? (visible ? 2 : 8) : (visible ? 1 : 0) }
    }
    static let thresholds = [100, 90, 80]
    static func shouldShow(level: Double, charging: Bool, threshold: Int, mode: Mode) -> Bool {
        !(level >= Double(threshold) && (mode == .always || charging))
    }
}

// Preserve absence as well as true/false, and retain recovery state until restoration succeeds.
final class PercentageHiderSession {
    typealias Setting = PercentageHiderPolicy.Setting
    private let defaults: UserDefaults
    private let read: (Setting) throws -> Int?
    private let write: (Setting, Int?) throws -> Void
    init(defaults: UserDefaults, read: @escaping (Setting) throws -> Int?, write: @escaping (Setting, Int?) throws -> Void) {
        self.defaults = defaults; self.read = read; self.write = write
    }
    func update(target: PercentageHiderPolicy.Target, visible: Bool) throws {
        for setting in Setting.allCases {
            if target.settings.contains(setting) { try apply(visible, to: setting) }
            else { try restore(setting) }
        }
    }
    private func originalKey(_ setting: Setting) -> String { "percentageHider.original." + setting.rawValue }
    private func saved(_ setting: Setting) throws -> Int? {
        guard let object = defaults.object(forKey: originalKey(setting)) else { return nil }
        guard let value = object as? Int, (setting == .percentage ? [-1, 0, 1] : [-1, 2, 8]).contains(value) else { throw Failure("The saved battery display setting is invalid.") }
        return value
    }
    private func apply(_ visible: Bool, to setting: Setting) throws {
        let current = try read(setting)
        if try saved(setting) == nil {
            defaults.set(current ?? -1, forKey: originalKey(setting))
        }
        if setting.visible(current) != visible {
            guard defaults.synchronize() else { throw Failure("Could not save the original battery display setting.") }
            try write(setting, setting.value(visible: visible))
        }
    }
    private func restore(_ setting: Setting) throws {
        guard let value = try saved(setting) else { return }
        let original: Int? = value == -1 ? nil : value
        if try read(setting) != original { try write(setting, original) }
        defaults.removeObject(forKey: originalKey(setting))
    }
    func isHiding() throws -> Bool {
        for setting in Setting.allCases {
            if try saved(setting) != nil, !setting.visible(try read(setting)) { return true }
        }
        return false
    }
    func restore() throws {
        // Attempt both restorations even if one fails; keep failed recovery records.
        var failure: Error?
        for setting in Setting.allCases {
            do { try restore(setting) } catch { failure = error }
        }
        if let failure { throw failure }
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}

final class PercentageHiderPill {
    typealias Mode = PercentageHiderPolicy.Mode
    typealias Target = PercentageHiderPolicy.Target
    typealias Setting = PercentageHiderPolicy.Setting
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "PercentageHider.control", qos: .utility)
    private let session: PercentageHiderSession
    private var source: CFRunLoopSource?
    private var stopping = false
    private(set) var enabled: Bool
    private(set) var threshold: Int
    private(set) var mode: Mode
    private(set) var target: Target
    private(set) var batteryStatus: (level: Double, charging: Bool, onExternalPower: Bool)?
    private(set) var isHiding = false
    private(set) var errorMessage: String?
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "percentageHider.enabled")
        let saved = defaults.integer(forKey: "percentageHider.threshold")
        threshold = PercentageHiderPolicy.thresholds.contains(saved) ? saved : 90
        mode = defaults.string(forKey: "percentageHider.mode").flatMap(Mode.init(rawValue:)) ?? .always
        target = defaults.string(forKey: "percentageHider.target").flatMap(Target.init(rawValue:)) ?? .percentage
        session = PercentageHiderSession(defaults: defaults, read: Self.readPreference, write: Self.writePreference)
    }
    func start() {
        guard source == nil else { return }
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PercentageHiderPill>.fromOpaque(context).takeUnretainedValue().refresh()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        refresh()
    }
    func setEnabled(_ value: Bool) {
        enabled = value; defaults.set(value, forKey: "percentageHider.enabled"); refresh()
    }
    func setThreshold(_ value: Int) {
        guard PercentageHiderPolicy.thresholds.contains(value) else { return }
        threshold = value; defaults.set(value, forKey: "percentageHider.threshold"); refresh()
    }
    func setMode(_ value: Mode) {
        mode = value; defaults.set(value.rawValue, forKey: "percentageHider.mode"); refresh()
    }
    func setTarget(_ value: Target) {
        target = value; defaults.set(value.rawValue, forKey: "percentageHider.target"); refresh()
    }
    func refreshBatteryStatus() { batteryStatus = enabled ? Self.battery() : nil }

    private func refresh() {
        guard !stopping else { return }
        let enabled = enabled, threshold = threshold, mode = mode, target = target, available = source != nil
        refreshBatteryStatus()
        let battery = batteryStatus
        queue.async {
            let error: String?
            var hiding = false
            do {
                if enabled && !available {
                    try self.session.restore()
                    throw PercentageHiderSession.Failure("Battery change notifications are unavailable.")
                }
                if enabled, let battery {
                    let visible = PercentageHiderPolicy.shouldShow(
                        level: battery.level, charging: battery.charging, threshold: threshold, mode: mode)
                    try self.session.update(target: target, visible: visible)
                    hiding = !visible
                } else { try self.session.restore() }
                error = nil
            } catch let failure {
                error = failure.localizedDescription
                hiding = (try? self.session.isHiding()) ?? false
            }
            let actualHiding = hiding
            DispatchQueue.main.async { self.errorMessage = error; self.isHiding = actualHiding; self.onChange?() }
        }
    }
    func stop(completion: @escaping (Error?) -> Void) {
        stopping = true
        if let source { CFRunLoopSourceInvalidate(source); self.source = nil }
        queue.async {
            var failure: Error?
            do { try self.session.restore() } catch { failure = error }
            DispatchQueue.main.async { completion(failure) }
        }
    }
    private static func battery() -> (level: Double, charging: Bool, onExternalPower: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = data[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = data[kIOPSMaxCapacityKey] as? Double,
                  let charging = data[kIOPSIsChargingKey] as? Bool,
                  maximum > 0, current >= 0, current <= maximum else { continue }
            let onExternalPower = (data[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (100 * current / maximum, charging, onExternalPower)
        }
        return nil
    }
    static func readPreference(_ setting: Setting) throws -> Int? {
        let domain = "com.apple.controlcenter" as CFString
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else {
            throw PercentageHiderSession.Failure("Could not read the battery display setting.")
        }
        guard let value = CFPreferencesCopyValue(setting.key as CFString, domain,
                                                kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { return nil }
        guard let number = value as? NSNumber,
              (setting == .percentage ? [0, 1] : [2, 8]).contains(number.intValue),
              number.doubleValue == Double(number.intValue) else {
            throw PercentageHiderSession.Failure("The battery display setting is unsupported.")
        }
        return number.intValue
    }
    static func writePreference(_ setting: Setting, _ value: Int?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        if let value {
            process.arguments = ["-currentHost", "write", "com.apple.controlcenter", setting.key,
                                 setting == .percentage ? "-bool" : "-int",
                                 setting == .percentage ? (value == 1 ? "true" : "false") : String(value)]
        } else { process.arguments = ["-currentHost", "delete", "com.apple.controlcenter", setting.key] }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PercentageHiderSession.Failure("Could not change the battery display setting.")
        }
    }
    deinit { if let source { CFRunLoopSourceInvalidate(source) } }
}
