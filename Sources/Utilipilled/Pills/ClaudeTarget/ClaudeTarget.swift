import Foundation

enum ClaudeTarget {
    // Wednesday, 1970-01-07 at 16:00 UTC. Fixed UTC arithmetic avoids timezone/DST changes.
    private static let resetAnchor: TimeInterval = 576_000
    private static let week: TimeInterval = 7 * 24 * 60 * 60

    static func percentage(at date: Date) -> Double {
        let remainder = (date.timeIntervalSince1970 - resetAnchor).truncatingRemainder(dividingBy: week)
        let elapsed = remainder < 0 ? remainder + week : remainder
        return elapsed / week * 100
    }

    static func title(at date: Date = Date(), label: String = "ClaudeMaxxing") -> String {
        "\(label): \(Int(percentage(at: date).rounded()))%"
    }
}
