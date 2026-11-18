import AppKit
import ApplicationServices
import Darwin

// All private entry points live here, are resolved at runtime, and are used only
// on the explicitly supported OS. No preferences or Dock state are mutated.
final class NativeSwitcherServices {
    static let shared = NativeSwitcherServices()
    private typealias CopyOrder = @convention(c) (UInt32, UInt64) -> Unmanaged<CFArray>?
    private typealias ASNType = @convention(c) () -> CFTypeID
    private typealias ExtractASN = @convention(c) (CFTypeRef, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> Void
    private typealias ProcessPID = @convention(c) (UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>) -> Int32
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32
    private typealias FrontProcess = @convention(c) (UnsafePointer<ProcessSerialNumber>, UInt32) -> Int32
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Void
    private let launchServices: UnsafeMutableRawPointer?
    private let applicationServices: UnsafeMutableRawPointer?
    private let copyOrder: CopyOrder?
    private let asnType: ASNType?
    private let extractASN: ExtractASN?
    private let processPID: ProcessPID?
    private let processForPID: ProcessForPID?
    private let frontProcess: FrontProcess?
    private let dockNotification: DockNotification?

    var supportsOverview: Bool { dockNotification != nil }
    var supportsInitialOrder: Bool { copyOrder != nil && asnType != nil && extractASN != nil && processPID != nil }

    private init() {
        launchServices = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY | RTLD_LOCAL)
        applicationServices = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY | RTLD_LOCAL)
        func resolve<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        copyOrder = resolve(launchServices, "_LSCopyApplicationArrayInFrontToBackOrder", as: CopyOrder.self)
        asnType = resolve(launchServices, "_LSASNGetTypeID", as: ASNType.self)
        extractASN = resolve(launchServices, "_LSASNExtractHighAndLowParts", as: ExtractASN.self)
        processPID = resolve(applicationServices, "GetProcessPID", as: ProcessPID.self)
        processForPID = resolve(applicationServices, "GetProcessForPID", as: ProcessForPID.self)
        frontProcess = resolve(applicationServices, "SetFrontProcessWithOptions", as: FrontProcess.self)
        dockNotification = resolve(applicationServices, "CoreDockSendNotification", as: DockNotification.self)
    }

    func initialApplicationOrder() -> [pid_t]? {
        guard Self.supportedOS, let copyOrder, let asnType, let extractASN, let processPID,
              let array = copyOrder(UInt32.max, 0)?.takeRetainedValue() else { return nil }
        var result: [pid_t] = []
        var seen: Set<pid_t> = []
        let expectedType = asnType()
        for index in 0..<CFArrayGetCount(array) {
            guard let raw = CFArrayGetValueAtIndex(array, index) else { return nil }
            let asn = Unmanaged<CFTypeRef>.fromOpaque(raw).takeUnretainedValue()
            guard CFGetTypeID(asn) == expectedType else { return nil }
            var psn = ProcessSerialNumber(); var pid: pid_t = 0
            extractASN(asn, &psn.highLongOfPSN, &psn.lowLongOfPSN)
            if processPID(&psn, &pid) == noErr, pid > 0, seen.insert(pid).inserted { result.append(pid) }
        }
        return result.isEmpty ? nil : result
    }

    @discardableResult
    func activateApplication(_ pid: pid_t) -> Bool {
        guard Self.supportedOS, let processForPID, let frontProcess else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr else { return false }
        // Legacy Process Manager's documented user-initiated activation flag. It
        // delegates ordering/Spaces to the system without targeting individual windows.
        return frontProcess(&psn, 1 << 1) == noErr
    }

    @discardableResult
    func showApplicationOverview() -> Bool {
        guard Self.supportedOS, let dockNotification else { return false }
        dockNotification("com.apple.expose.front.awake" as CFString, 0)
        return true
    }

    static var supportedOS: Bool {
        #if arch(arm64)
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
        #else
        return false
        #endif
    }

    deinit {
        if let launchServices { dlclose(launchServices) }
        if let applicationServices { dlclose(applicationServices) }
    }
}
