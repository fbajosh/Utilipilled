import Foundation

/// Aggregates all cameras, with immediate activation and a brief all-idle grace period.
public struct CameraPolicy {
    public private(set) var active = false
    private var idleSince: TimeInterval?
    private var unknownSince: TimeInterval?
    public init() {}
    /// `now` must be monotonic elapsed time, never calendar time. Clock corrections
    /// must not extend a mute after the camera stops or postpone the error timeout.
    public mutating func update(runningCount: Int, reliable: Bool,
                                now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> Bool {
        if runningCount > 0 {
            active = true; idleSince = nil; unknownSince = nil
        } else if reliable {
            unknownSince = nil
            if idleSince == nil { idleSince = now }
            if now - idleSince! >= 1.5 { active = false }
        } else {
            idleSince = nil
            if unknownSince == nil { unknownSince = now }
            if now - unknownSince! >= 5 {
                throw QuietError.failure("Camera state unavailable for 5 seconds. Automation paused; toggle Automatic quiet off and on to retry.")
            }
        }
        return active
    }
}
