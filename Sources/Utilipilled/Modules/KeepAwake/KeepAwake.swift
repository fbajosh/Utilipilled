import Foundation
import IOKit.pwr_mgt
import Darwin

final class KeepAwakeModule {
    enum Duration: String, CaseIterable {
        case halfHour = "30 min", twelveHours = "12 hours"
        case untilRestart = "Until restart", indefinitely = "Indefinitely"
        var seconds: TimeInterval? {
            switch self {
            case .halfHour: return 30 * 60
            case .twelveHours: return 12 * 60 * 60
            default: return nil
            }
        }
    }
    private let defaults: UserDefaults
    private var assertion: IOPMAssertionID?
    private var timer: Timer?
    private var deadline: Date?
    private(set) var duration: Duration
    var isEnabled: Bool { assertion != nil }
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        duration = defaults.string(forKey: "keepAwake.duration").flatMap(Duration.init(rawValue:)) ?? .untilRestart
    }

    func resume() throws {
        guard defaults.bool(forKey: "keepAwake.active") else { return }
        if duration == .untilRestart {
            guard let boot = Self.bootID, defaults.string(forKey: "keepAwake.boot") == boot else {
                defaults.set(false, forKey: "keepAwake.active"); return
            }
        }
        if duration.seconds != nil {
            guard let saved = defaults.object(forKey: "keepAwake.deadline") as? Date, saved > Date() else {
                defaults.set(false, forKey: "keepAwake.active"); return
            }
            deadline = saved
        }
        try acquire()
    }

    func setDuration(_ value: Duration) throws {
        let previous = duration
        let previousDeadline = deadline
        duration = value
        deadline = nil
        do { if isEnabled { try acquire() } }
        catch { duration = previous; deadline = previousDeadline; throw error }
        defaults.set(value.rawValue, forKey: "keepAwake.duration")
        onChange?()
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard !isEnabled else { return }
            deadline = nil
            try acquire()
        } else {
            try release()
            defaults.set(false, forKey: "keepAwake.active")
            deadline = nil
        }
        onChange?()
    }

    // Release the process-owned request on quit, retaining the selected session for relaunch.
    func suspend() { try? release() }

    func checkExpiration() {
        guard isEnabled, let deadline, deadline <= Date() else { return }
        // The system timeout already expires the native assertion, including during sleep.
        suspend()
        defaults.set(false, forKey: "keepAwake.active")
        onChange?()
    }

    private func acquire() throws {
        let end = duration.seconds.map { seconds in deadline ?? Date().addingTimeInterval(seconds) }
        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            "Utilipilled Keep Awake" as CFString, nil, nil, nil,
            end.map { max(0.001, $0.timeIntervalSinceNow) } ?? 0,
            kIOPMAssertionTimeoutActionTurnOff as CFString, &identifier)
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
        do { try release() }
        catch { IOPMAssertionRelease(identifier); throw error }
        assertion = identifier
        deadline = end
        defaults.set(true, forKey: "keepAwake.active")
        defaults.set(duration.rawValue, forKey: "keepAwake.duration")
        defaults.set(Self.bootID, forKey: "keepAwake.boot")
        defaults.set(end, forKey: "keepAwake.deadline")
        if let end {
            let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in self?.checkExpiration() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func release() throws {
        if let assertion {
            let result = IOPMAssertionRelease(assertion)
            guard result == kIOReturnSuccess else { throw Failure(code: result) }
            self.assertion = nil
        }
        timer?.invalidate(); timer = nil
    }

    private static var bootID: String? {
        var count = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &count, nil, 0) == 0, count > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: count)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &count, nil, 0) == 0 else { return nil }
        return String(cString: bytes)
    }
    deinit { timer?.invalidate(); if let assertion { IOPMAssertionRelease(assertion) } }
    private struct Failure: LocalizedError {
        let code: IOReturn
        var errorDescription: String? { "macOS could not change sleep prevention (error \(code))." }
    }
}
