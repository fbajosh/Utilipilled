import AppKit
import ApplicationServices

struct SwitcherAvailability {
    var supported: () -> Bool
    var trusted: () -> Bool
    var requestPermission: () -> Void
    var nativeInterfacesAvailable: () -> Bool

    static let system = SwitcherAvailability(
        supported: { NativeSwitcherServices.supportedOS },
        trusted: { AXIsProcessTrusted() },
        requestPermission: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        nativeInterfacesAvailable: {
            NativeSwitcherServices.shared.supportsInitialOrder && NativeSwitcherServices.shared.supportsOverview && NativeSwitcherGlass.isAvailable
        })
}

protocol SwitcherKeyboardInterception: AnyObject {
    var begin: ((Bool) -> Bool)? { get set }
    var isSwitching: (() -> Bool)? { get set }
    var move: ((Int) -> Void)? { get set }
    var finish: ((Bool) -> Void)? { get set }
    var cancel: (() -> Void)? { get set }
    var quitSelected: (() -> Void)? { get set }
    var hideSelected: (() -> Void)? { get set }
    var overview: (() -> Void)? { get set }
    var point: ((CGPoint, Bool) -> Bool)? { get set }
    var onFailure: (() -> Void)? { get set }
    var isRunning: Bool { get }
    func start() -> Bool
    func stop()
}

extension KeyboardInterceptor: SwitcherKeyboardInterception {}
