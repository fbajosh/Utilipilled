import Foundation
import IOKit.pwr_mgt

final class KeepAwakeModule {
    private var assertion: IOPMAssertionID?
    var isEnabled: Bool { assertion != nil }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled != isEnabled else { return }
        let result: IOReturn
        if enabled {
            var identifier: IOPMAssertionID = 0
            result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Utilipilled Keep Awake" as CFString,
                &identifier
            )
            if result == kIOReturnSuccess { assertion = identifier }
        } else if let identifier = assertion {
            result = IOPMAssertionRelease(identifier)
            if result == kIOReturnSuccess { assertion = nil }
        } else {
            return
        }
        guard result == kIOReturnSuccess else { throw Failure(code: result) }
    }

    deinit {
        if let assertion { IOPMAssertionRelease(assertion) }
    }

    private struct Failure: LocalizedError {
        let code: IOReturn
        var errorDescription: String? { "macOS could not change sleep prevention (error \(code))." }
    }
}
