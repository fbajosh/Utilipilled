import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]), pid > 0 else {
    fputs("Usage: SwitcherTapProbe PID\n", stderr); exit(2)
}
var count: UInt32 = 0
guard CGGetEventTapList(0, nil, &count) == .success else {
    fputs("macOS did not provide the event tap list\n", stderr); exit(1)
}
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
let error = taps.withUnsafeMutableBufferPointer { CGGetEventTapList(count, $0.baseAddress, &count) }
guard error == .success else { fputs("Event tap read failed\n", stderr); exit(1) }
let matching: [[String: Any]] = taps.prefix(Int(count)).filter { $0.tappingProcess == pid }.map {
    ["id": $0.eventTapID, "enabled": $0.enabled, "tapPoint": $0.tapPoint.rawValue,
     "minimum_callback_us": $0.minUsecLatency, "mean_callback_us": $0.avgUsecLatency,
     "maximum_callback_us": $0.maxUsecLatency]
}
let data = try JSONSerialization.data(withJSONObject: ["pid": pid, "taps": matching], options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
