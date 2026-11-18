import Foundation

@main
enum ClaudeTargetChecks {
    static func main() {
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) -> Date { formatter.date(from: value)! }
        // Monday 22:17 at fixed UTC-5, including during US daylight saving time.
        for timestamp in ["2026-11-17T03:17:00Z", "2026-07-21T03:17:00Z"] {
            let instant = date(timestamp)
            precondition(ClaudeTarget.title(at: instant) == "ClaudeMaxxing: 78%")
            precondition(abs(ClaudeTarget.percentage(at: instant) - 78.15) < 0.01)
        }
        let reset = date("2026-11-18T16:00:00Z")
        precondition(ClaudeTarget.percentage(at: reset) == 0)
        precondition(ClaudeTarget.title(at: reset.addingTimeInterval(-1)) == "ClaudeMaxxing: 100%")
        precondition(ClaudeTarget.title(at: reset.addingTimeInterval(302_400)) == "ClaudeMaxxing: 50%")
        precondition(ClaudeTarget.percentage(at: reset.addingTimeInterval(604_800)) == 0)
        precondition(ClaudeTarget.title(at: date("1970-01-06T03:17:00Z")) == "ClaudeMaxxing: 78%")
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        for zone in ["America/New_York", "America/Los_Angeles", "Europe/London", "Asia/Tokyo"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            precondition(ClaudeTarget.title(at: date("2026-07-21T03:17:00Z")) == "ClaudeMaxxing: 78%")
            precondition(ClaudeTarget.percentage(at: reset) == 0)
        }
        print("ClaudeMaxxing Monday example, Wednesday reset, week boundary, DST and timezone checks passed")
    }
}
